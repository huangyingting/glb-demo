set -e

CHOWN=$(/usr/bin/which chown)
E2GUARD=$(/usr/bin/which e2guardian)

prepare_folders() {
	echo "Preparing folders..."
	mkdir -p /etc/e2guardian/private/
	mkdir -p /etc/e2guardian/private/generatedcerts/
	"$CHOWN" -R e2guard:e2guard /etc/e2guardian/private
}

create_cert() {
	echo "Creating certificate..."
    if [ ! -f /etc/e2guardian/private/ca.key ]; then
        openssl genrsa 2048 > /etc/e2guardian/private/ca.key
    fi

    if [ ! -f /etc/e2guardian/private/ca.pem ]; then
        openssl req -new -x509 -days 3650 -key /etc/e2guardian/private/ca.key \
            -out /etc/e2guardian/private/ca.pem \
            -subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=$CN"
        openssl x509 -in /etc/e2guardian/private/ca.pem -outform DER -out /etc/e2guardian/private/ca.der
        openssl x509 -inform PEM -in /etc/e2guardian/private/ca.pem -out /usr/local/share/ca-certificates/ca.crt
        update-ca-certificates
    fi

    if [ ! -f /etc/e2guardian/private/cert.key ]; then
        openssl genrsa 2048 > /etc/e2guardian/private/cert.key
    fi
	
}

run() {
	echo "Starting e2guardian..."
	prepare_folders
	create_cert
	exec "$E2GUARD"
}

run
