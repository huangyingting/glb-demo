#!/bin/sh

# Parameters
frontend_ip="52.187.64.200"
mitm_ip="240.0.0.1"
mitm_net="0.0.0.0/0"
pseudo_mac="0x123456789abc"
mitm_port_mac="60:60:60:60:60:60"

# Create OVS vxlan port for gateway load balancer inbound and outbound tunnels
ovs-vsctl add-br br-glb
ovs-vsctl add-port br-glb glb-int -- set interface glb-int type=vxlan options:remote_ip=10.110.1.128 options:key=800 options:dst_port=10800
ovs-vsctl add-port br-glb glb-ext -- set interface glb-ext type=vxlan options:remote_ip=10.110.1.128 options:key=801 options:dst_port=10801

# Configure mitm as local routers
ovs-vsctl add-port br-glb mitm -- set Interface mitm type=internal
ip link set dev mitm address ${mitm_port_mac}
ip addr add ${mitm_ip} dev mitm
ip link set mitm up
ip route add ${mitm_net} dev mitm scope link table mitmrt
ip rule add from ${mitm_ip} to 0.0.0.0/0 lookup mitmrt
ip route add ${frontend_ip} dev mitm

# Reset flow table
ovs-ofctl del-flows br-glb

# Create a pseudo gateway for loc_int_net, respond to ARP request and ICMP ping
ovs-ofctl add-flow br-glb "table=0,priority=0,actions=NORMAL"
ovs-ofctl add-flow br-glb "table=0,in_port=mitm,arp,arp_tpa=${mitm_net},arp_op=1 actions=move:NXM_OF_ETH_SRC[]->NXM_OF_ETH_DST[],set_field:${mitm_port_mac}->eth_src,load:0x2->NXM_OF_ARP_OP[],move:NXM_NX_ARP_SHA[]->NXM_NX_ARP_THA[],load:0x123456789abc->NXM_NX_ARP_SHA[],push:NXM_OF_ARP_SPA[],push:NXM_OF_ARP_TPA[],pop:NXM_OF_ARP_SPA[],pop:NXM_OF_ARP_TPA[],IN_PORT"
ovs-ofctl add-flow br-glb "table=0,in_port=mitm,icmp,nw_dst=${mitm_net},icmp_type=8,icmp_code=0,actions=push:NXM_OF_ETH_SRC[],push:NXM_OF_ETH_DST[],pop:NXM_OF_ETH_SRC[],pop:NXM_OF_ETH_DST[],push:NXM_OF_IP_SRC[],push:NXM_OF_IP_DST[],pop:NXM_OF_IP_SRC[],pop:NXM_OF_IP_DST[],load:0xff->NXM_NX_IP_TTL[],load:0->NXM_OF_ICMP_TYPE[],IN_PORT"

# Redirect glb inbound traffic, dnat
# Inbound
ovs-ofctl add-flow br-glb "table=0,in_port=glb-ext,tcp,tp_dst=80,nw_dst=${frontend_ip},actions=ct(commit,table=1,zone=1,nat(dst=${mitm_ip}:6080))"
ovs-ofctl add-flow br-glb "table=1,tcp,tp_dst=6080,nw_dst=${mitm_ip},ct_zone=1,actions=mod_dl_dst:${mitm_port_mac},mitm"
# Outbound
ovs-ofctl add-flow br-glb "table=0,in_port=mitm,tcp,tp_src=6080,nw_src=${mitm_ip},actions=ct(table=1,zone=1,nat)"
ovs-ofctl add-flow br-glb "table=1,in_port=mitm,tcp,tcp_src=80,nw_src=${frontend_ip},ct_zone=1,actions=glb-ext"
# Direct to backend
ovs-ofctl add-flow br-glb "table=0,in_port=mitm,tcp,tp_dst=6080,nw_src=${mitm_ip},nw_dst=${frontend_ip},actions=glb-int"
ovs-ofctl add-flow br-glb "table=0,in_port=glb-int,tcp,tp_src=6080,nw_src=${frontend_ip},nw_dst=${mitm_ip},actions=mod_dl_dst:${mitm_port_mac},mitm"

cat <<EOF > Caddyfile
{
  auto_https off
}

:6080 {
  reverse_proxy http://$frontend_ip:6080
}
EOF

docker run -d --net=host --name caddy -v $PWD/Caddyfile:/etc/caddy/Caddyfile caddy:alpine
docker stop caddy
docker rm caddy
ip route delete ${frontend_ip} dev mitm
ip rule delete from ${mitm_ip} to 0.0.0.0/0 lookup mitmrt
ip route delete ${mitm_net} dev mitm scope link table mitmrt
ovs-vsctl del-br br-glb

