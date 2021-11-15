# glb-demo
Azure Gateway Load Balancer Demo

## Deploy guide
1. Copy public key into root folder and rename it to key-data
2. Create a resource group on your exisitng subscription "az group create -l southeastasia -n GLB"
3. "az deployment group create -g GLB --template-file gatewaylb.bicep" to deploy a linux provider or if you want to deploy opnsense run "az deployment group create -g GLB --template-file opnsese.bicep"

## Demo guide(Linux)
1. From Azure portal, find ProviderVM, SSH into it with your private key
2. From Azure portal, find ConsumerVM, SSH into it with your private key
3. As for now, it works without any issue
4. Now run "sudo iptables -A FORWARD -i br0 -p tcp -d {consumer vm public ip} --dport 22 -j DROP", replace {consumer vm public ip} with consumer VM public ip address
5. The SSH session to ConsumerVM stops working, as we blocked incoming traffic to ConsumerVM


## Demo guide(OPNSense)
1. From Azure portal, find OPNSense, https://<public ip>, default username is root and password is opnsense
2. Create a firewall rule from glbint or glbext to block traffics ConumserVm
