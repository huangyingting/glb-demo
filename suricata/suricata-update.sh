suricata-update update-sources
suricata-update
suricatasc -c ruleset-reload-nonblocking
logrotate /etc/logrotate.conf --state /var/log/logrotate.state --verbose