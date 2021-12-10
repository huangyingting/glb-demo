#!/usr/bin/dumb-init /bin/sh
set -e

update_suricata_rules() {
	echo "Update suricata rules"
    suricata-update
    crond -b
    crontab /etc/crontabs/suricata-cronjobs
}

start_suricata()
{    
    if [ "${1#-}" != "$1" ]; then
        set -- suricata "$@"
    elif [ "$1" = 'suricata' ]; then
        shift
        set -- suricata "$@"
    fi
    echo "Start suricata with command line: $@"
    exec "$@"
}

update_suricata_rules
start_suricata "$@"
