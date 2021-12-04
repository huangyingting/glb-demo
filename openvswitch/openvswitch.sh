#!/bin/sh

# Parameters
frontend_ip="52.187.64.200"
loc_int_net="172.16.70.0/24"
loc_ext_net="172.16.80.0/24"
loc_int_nat_range="172.16.70.20-172.16.70.120"
loc_ext_nat_range="172.16.80.20-172.16.80.120"
pseudo_int_net_mac="0x123456789abc"
pseudo_ext_net_mac="0x123456789abc"
loc_int_port_mac="70:70:70:70:70:70"
loc_ext_port_mac="80:80:80:80:80:80"

# Create OVS vxlan ports for gateway load balancer inbound and outbound tunnels
ovs-vsctl add-br br-glb
ovs-vsctl add-port br-glb glb-int -- set interface glb-int type=vxlan options:remote_ip=10.110.1.128 options:key=800 options:dst_port=10800
ovs-vsctl add-port br-glb glb-ext -- set interface glb-ext type=vxlan options:remote_ip=10.110.1.128 options:key=801 options:dst_port=10801

# Configure loc-int and loc-ext as local routers
ovs-vsctl add-port br-glb loc-int -- set Interface loc-int type=internal
ip link set dev loc-int address ${loc_int_port_mac}
ip link set loc-int up
ip route add ${loc_int_net} dev loc-int scope link

ovs-vsctl add-port br-glb loc-ext -- set Interface loc-ext type=internal
ip link set dev loc-ext address ${loc_ext_port_mac}
ip link set loc-ext up
ip route add ${loc_ext_net} dev loc-ext scope link

# Reset flow table and iptables
iptables -t nat -F
iptables -t nat -D POSTROUTING -p tcp -s ${loc_int_net} --dport 80 -o eth0 -j MASQUERADE
iptables -t nat -D PREROUTING -p tcp -s ${loc_ext_net} -d ${frontend_ip} --dport 80 -i loc-ext -j DNAT --to-destination 127.0.0.1:6080

ovs-ofctl del-flows br-glb

# Iptables
iptables -t nat -A POSTROUTING -p tcp -s ${loc_int_net} --dport 80 -o eth0 -j MASQUERADE

iptables -t nat -A PREROUTING -p tcp -s ${loc_ext_net} -d ${frontend_ip} --dport 80 -i loc-ext -j DNAT --to-destination 127.0.0.1:6080

# Create a pseudo gateway for loc_int_net, respond to ARP request and ICMP ping
ovs-ofctl add-flow br-glb "table=0,priority=0,actions=NORMAL"

ovs-ofctl add-flow br-glb "table=0,in_port=loc-int,arp,arp_tpa=${loc_int_net},arp_op=1 actions=move:NXM_OF_ETH_SRC[]->NXM_OF_ETH_DST[],set_field:${loc_int_port_mac}->eth_src,load:0x2->NXM_OF_ARP_OP[],move:NXM_NX_ARP_SHA[]->NXM_NX_ARP_THA[],load:0x123456789abc->NXM_NX_ARP_SHA[],push:NXM_OF_ARP_SPA[],push:NXM_OF_ARP_TPA[],pop:NXM_OF_ARP_SPA[],pop:NXM_OF_ARP_TPA[],IN_PORT"

ovs-ofctl add-flow br-glb "table=0,in_port=loc-int,icmp,nw_dst=${loc_int_net},icmp_type=8,icmp_code=0,actions=push:NXM_OF_ETH_SRC[],push:NXM_OF_ETH_DST[],pop:NXM_OF_ETH_SRC[],pop:NXM_OF_ETH_DST[],push:NXM_OF_IP_SRC[],push:NXM_OF_IP_DST[],pop:NXM_OF_IP_SRC[],pop:NXM_OF_IP_DST[],load:0xff->NXM_NX_IP_TTL[],load:0->NXM_OF_ICMP_TYPE[],IN_PORT"

ovs-ofctl add-flow br-glb "table=0,in_port=loc-ext,arp,arp_tpa=${loc_ext_net},arp_op=1 actions=move:NXM_OF_ETH_SRC[]->NXM_OF_ETH_DST[],set_field:${loc_ext_port_mac}->eth_src,load:0x2->NXM_OF_ARP_OP[],move:NXM_NX_ARP_SHA[]->NXM_NX_ARP_THA[],load:0x123456789abc->NXM_NX_ARP_SHA[],push:NXM_OF_ARP_SPA[],push:NXM_OF_ARP_TPA[],pop:NXM_OF_ARP_SPA[],pop:NXM_OF_ARP_TPA[],IN_PORT"

ovs-ofctl add-flow br-glb "table=0,in_port=loc-ext,icmp,nw_dst=${loc_ext_net},icmp_type=8,icmp_code=0,actions=push:NXM_OF_ETH_SRC[],push:NXM_OF_ETH_DST[],pop:NXM_OF_ETH_SRC[],pop:NXM_OF_ETH_DST[],push:NXM_OF_IP_SRC[],push:NXM_OF_IP_DST[],pop:NXM_OF_IP_SRC[],pop:NXM_OF_IP_DST[],load:0xff->NXM_NX_IP_TTL[],load:0->NXM_OF_ICMP_TYPE[],IN_PORT"


# Redirect glb outbound traffic, snat
# Outbound
ovs-ofctl add-flow br-glb "table=0,in_port=glb-int,tcp,tp_dst=80,nw_src=${frontend_ip},actions=ct(commit,table=1,zone=1,nat(src=${loc_int_nat_range}))"
ovs-ofctl add-flow br-glb "table=1,tcp,tp_dst=80,nw_src=${loc_int_net},ct_zone=1,actions=mod_dl_dst:${loc_int_port_mac},loc-int"
# Inbound
ovs-ofctl add-flow br-glb "table=0,in_port=loc-int,tcp,tp_src=80,nw_dst=${loc_int_net},actions=ct(table=1,zone=1,nat)"
ovs-ofctl add-flow br-glb "table=1,in_port=loc-int,tcp,tcp_src=80,nw_dst=${frontend_ip},ct_zone=1,actions=glb-int"

# Redirect glb outbound traffic, stateful snat with ct_state
# Outbound
ovs-ofctl add-flow br-glb "table=0,in_port=glb-int,tcp,tp_dst=80,nw_src=${frontend_ip},ct_state=-trk,actions=ct(table=1,zone=1,nat)"
ovs-ofctl add-flow br-glb "table=1,in_port=glb-int,tcp,tp_dst=80,nw_src=${frontend_ip},ct_state=+trk+new,ct_zone=1,actions=ct(commit,table=1,zone=1,nat(src=${loc_int_nat_range})),mod_dl_dst:${loc_int_port_mac},loc-int"
ovs-ofctl add-flow br-glb "table=1, in_port=glb-int,tcp,tcp_dst=80,nw_src=${loc_int_net},ct_state=+trk+est,ct_zone=1,actions=mod_dl_dst:${loc_int_port_mac},loc-int"
# Inbound
ovs-ofctl add-flow br-glb "table=0,in_port=loc-int,tcp,tp_src=80,nw_dst=${loc_int_net},ct_state=+trk,actions=ct(table=1,zone=1,nat)"
ovs-ofctl add-flow br-glb "table=1,in_port=loc-int,tcp,tcp_src=80,nw_dst=${frontend_ip},ct_zone=1,ct_state=+trk+est,actions=glb-int"

# Redirect glb inbound traffic, snat
# Inbound
ovs-ofctl add-flow br-glb "table=0,in_port=glb-ext,tcp,tp_dst=80,nw_dst=${frontend_ip},actions=ct(commit,table=1,zone=1,nat(src=${loc_ext_nat_range}))"
ovs-ofctl add-flow br-glb "table=1,tcp,tp_dst=80,nw_dst=${frontend_ip},ct_zone=1,actions=mod_dl_dst:${loc_ext_port_mac},loc-ext"
# Outbound
ovs-ofctl add-flow br-glb "table=0,in_port=loc-ext,tcp,tp_src=80,nw_src=${frontend_ip},actions=ct(table=1,zone=1,nat)"
ovs-ofctl add-flow br-glb "table=1,in_port=loc-ext,tcp,tcp_src=80,nw_src=${frontend_ip},ct_zone=1,actions=glb-ext"

# Redirect glb inbound traffic, stateful snat with ct_state
# Inbound
ovs-ofctl add-flow br-glb "table=0,in_port=glb-ext,tcp,tp_dst=80,nw_dst=${frontend_ip},ct_state=-trk,actions=ct(table=1,zone=1,nat)"
ovs-ofctl add-flow br-glb "table=1,in_port=glb-ext,tcp,tp_dst=80,nw_dst=${frontend_ip},ct_state=+trk+new,ct_zone=1,actions=ct(commit,table=1,zone=1,nat(src=${loc_ext_nat_range})),mod_dl_dst:${loc_ext_port_mac},loc-ext"
ovs-ofctl add-flow br-glb "table=1, in_port=glb-ext,tcp,tcp_dst=80,nw_src=${loc_ext_net},nw_dst=${frontend_ip},ct_state=+trk+est,ct_zone=1,actions=mod_dl_dst:${loc_ext_port_mac},loc-ext"
# Outbound
ovs-ofctl add-flow br-glb "table=0,in_port=loc-ext,tcp,tp_src=80,nw_dst=${loc_ext_net},nw_src=${frontend_ip},ct_state=+trk,actions=ct(table=1,zone=1,nat)"
ovs-ofctl add-flow br-glb "table=1,in_port=loc-ext,tcp,tcp_src=80,nw_src=${frontend_ip},ct_zone=1,ct_state=+trk+est,actions=glb-ext"

# Troubleshooting
#ovs-ofctl dump-flows br-glb
#ovs-appctl ofproto/trace br-glb in_port=loc-int,tcp,tp_src=80,nw_dst=172.16.80.2,nw_src=8.8.8.8