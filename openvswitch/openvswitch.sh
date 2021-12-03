#!/bin/sh

# Parameters
glb_int_ip="52.187.64.200"
loc_int_net="172.16.80.0/24"
loc_int_nat_range="172.16.80.20-172.16.80.120"
pseudo_int_net_mac="0x123456789abc"
loc_int_port_mac="80:80:80:80:80:80"

# Create OVS with vxlan tunnels for gateway load balancer
ovs-vsctl add-br br-glb
ovs-vsctl add-port br-glb glb-int -- set interface glb-int type=vxlan options:remote_ip=10.110.1.128 options:key=800 options:dst_port=10800
ovs-vsctl add-port br-glb glb-ext -- set interface glb-ext type=vxlan options:remote_ip=10.110.1.128 options:key=801 options:dst_port=10801

# Configure loc-int as a router
ovs-vsctl add-port br-glb loc-int -- set Interface loc-int type=internal
ip link set dev loc-int address ${loc_int_port_mac}
ip link set loc-int up
ip route add ${loc_int_net} dev loc-int scope link

# Reset flow table and iptables
iptables -t nat -F
ovs-ofctl del-flows br-glb

# Iptables
iptables -t nat -A POSTROUTING -p tcp -s ${loc_int_net} --dport 80 -o eth0 -j MASQUERADE

# Create a pseudo gateway for loc_int_net, respond to ARP request and ICMP ping
ovs-ofctl add-flow br-glb "table=0,priority=0,actions=NORMAL"

ovs-ofctl add-flow br-glb "table=0,in_port=loc-int,arp,arp_tpa=${loc_int_net},arp_op=1 actions=move:NXM_OF_ETH_SRC[]->NXM_OF_ETH_DST[],set_field:${loc_int_port_mac}->eth_src,load:0x2->NXM_OF_ARP_OP[],move:NXM_NX_ARP_SHA[]->NXM_NX_ARP_THA[],load:0x123456789abc->NXM_NX_ARP_SHA[],push:NXM_OF_ARP_SPA[],push:NXM_OF_ARP_TPA[],pop:NXM_OF_ARP_SPA[],pop:NXM_OF_ARP_TPA[],IN_PORT"

ovs-ofctl add-flow br-glb "table=0,in_port=loc-int,icmp,nw_dst=${loc_int_net},icmp_type=8,icmp_code=0,actions=push:NXM_OF_ETH_SRC[],push:NXM_OF_ETH_DST[],pop:NXM_OF_ETH_SRC[],pop:NXM_OF_ETH_DST[],push:NXM_OF_IP_SRC[],push:NXM_OF_IP_DST[],pop:NXM_OF_IP_SRC[],pop:NXM_OF_IP_DST[],load:0xff->NXM_NX_IP_TTL[],load:0->NXM_OF_ICMP_TYPE[],IN_PORT"

# Redirect glb outbound traffics to provider
ovs-ofctl add-flow br-glb "table=0,in_port=glb-int,tcp, tp_dst=80,nw_src=${glb_int_ip},actions=ct(commit,zone=1,table=1,nat(src=${loc_int_nat_range}))"

ovs-ofctl add-flow br-glb "table=0,in_port=loc-int,tcp,tp_src=80,nw_dst=${loc_int_net},actions=ct(nat,zone=1,table=1)"

ovs-ofctl add-flow br-glb "table=1,tcp,tp_dst=80,nw_src=${loc_int_net},ct_zone=1,actions=mod_dl_dst:${loc_int_port_mac},loc-int"

ovs-ofctl add-flow br-glb "table=1,in_port=loc-int,tcp,tcp_src=80,nw_dst=${glb_int_ip},ct_zone=1,actions=glb-int"

# Try another nat 
ovs-ofctl add-flow br-glb "table=0,in_port=glb-int,tcp,tp_dst=80,nw_src=${glb_int_ip},ct_state=-trk,actions=ct(zone=1,table=1)"

ovs-ofctl add-flow br-glb "table=1,in_port=glb-int,tcp,tp_dst=80,nw_src=${loc_int_net},ct_state=+trk+new,ct_zone=1,actions=ct(commit,zone=1,table=1,nat(src=${loc_int_nat_range}),mod_dl_dst:${loc_int_port_mac},loc-int"

ovs-ofctl add-flow br-glb "table=1, in_port=glb-int,tcp,tcp_dst=80,nw_src=${loc_int_net},ct_state=+trk+est,ct_zone=1,actions=mod_dl_dst:${loc_int_port_mac},loc-int"



ovs-ofctl add-flow br-glb "table=0,in_port=loc-int,tcp,tp_src=80,nw_dst=${loc_int_net},ct_state=-trk,actions=ct(nat,zone=1,table=1)"
ovs-ofctl add-flow br-glb "table=1,in_port=loc-int,tcp,tcp_src=80,nw_dst=${glb_int_ip},ct_zone=1,ct_state=+trk+est,actions=glb-int"
