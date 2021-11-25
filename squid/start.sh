set -e

CHOWN=$(/usr/bin/which chown)
SQUID=$(/usr/bin/which squid)
CP=$(/usr/bin/which cp)

prepare_folders() {
	echo "Preparing folders..."
	mkdir -p /opt/squid/cert/
	mkdir -p /opt/squid/cache/
	mkdir -p /opt/squid/log/
	mkdir -p /opt/squid/conf/
	"$CHOWN" -R squid:squid /opt/squid/cert
	"$CHOWN" -R squid:squid /opt/squid/cache
	"$CHOWN" -R squid:squid /opt/squid/log
	"$CHOWN" -R squid:squid /opt/squid/conf
}

initialize_cache() {
	echo "Creating cache folder..."
	"$SQUID" -z
	sleep 5
}

is_ip() {
    local ip=$1
 
    if expr "$ip" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
        for i in 1 2 3 4; do
            if [ $(echo "$ip" | cut -d. -f$i) -gt 255 ]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

update_localnet() {
    echo "Updating localnet config file..."
    echo "" > /opt/squid/conf/localnet.conf    
    for le in ${LOCAL_NET}
    do
        is_ip ${le}
        if [[ $? -eq 0 ]]; then
            echo "acl localnet src ${le}" >> /opt/squid/conf/localnet.conf
		else
			echo "Invalid ip address: ${le}"
        fi
    done
}

create_cert() {
	if [ ! -f /opt/squid/cert/squid_ca.pem ]; then
		echo "Creating certificate..."
		openssl req -new -newkey rsa:2048 -sha256 -days 3650 -nodes -x509 \
			-extensions v3_ca -keyout /opt/squid/cert/squid_ca.pem \
			-out /opt/squid/cert/squid_ca.pem \
			-subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=$CN" -utf8 -nameopt multiline,utf8
	else
		echo "Certificate found..."
	fi
	if [ ! -f /opt/squid/cert/squid_ca.crt ]; then
		openssl x509 -inform PEM -in /opt/squid/cert/squid_ca.pem -out /opt/squid/cert/squid_ca.crt
	fi
	"$CP" /opt/squid/cert/squid_ca.crt /usr/local/share/ca-certificates/squid_ca.crt
	update-ca-certificates
}

clear_certs_db() {
	echo "Clearing generated certificate db..."
	rm -rfv /opt/squid/cache/ssl_db/
	/usr/lib/squid/security_file_certgen -c -s /opt/squid/cache/ssl_db -M 4MB
	"$CHOWN" -R squid.squid /opt/squid/cache/ssl_db
}

run() {
	echo "Starting squid..."
	prepare_folders
	create_cert
	clear_certs_db
	update_localnet
	initialize_cache
	exec "$SQUID" --foreground -Y -C -d $DEBUG_LEVEL -f /etc/squid/squid.conf
}

run
