#!/bin/sh
docker run -d --name=suricata --restart=unless-stopped --net=host --cap-add=NET_ADMIN --cap-add=SYS_NICE --cap-add=NET_RAW huangyingting/suricata