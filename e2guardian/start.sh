set -e

prepare_folders() {
	echo "Preparing folders"

    if [ ! -d "/etc/e2guardian/private" ]; then
	    install -d -g "clamav" -m 775 -o "clamav" "/etc/e2guardian/private"
    fi

    if [ ! -d "/etc/e2guardian/private/generatedcerts" ]; then
	    install -d -g "clamav" -m 775 -o "clamav" "/etc/e2guardian/private/generatedcerts"
    fi

    if [ ! -d "/run/clamav" ]; then
	    install -d -g "clamav" -m 775 -o "clamav" "/run/clamav"
    fi

    # Assign ownership to the database directory, just in case it is a mounted volume
    chown -R clamav:clamav /var/lib/clamav
}

create_cert() {
	echo "Creating certificate"
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

start_clamav() {
	if [ ! -f "/var/lib/clamav/main.cvd" ]; then
		echo "Updating initial database"
		freshclam --foreground --stdout
	fi

    echo "Starting ClamAV"
    if [ -S "/run/clamav/clamd.sock" ]; then
        unlink "/run/clamav/clamd.sock"
    fi
    clamd --foreground &
    while [ ! -S "/run/clamav/clamd.sock" ]; do
        if [ "${_timeout:=0}" -gt "${CLAMD_STARTUP_TIMEOUT:=1800}" ]; then
            echo
            echo "Failed to start clamd"
            exit 1
        fi
        printf "\r%s" "Socket for clamd not found yet, retrying (${_timeout}/${CLAMD_STARTUP_TIMEOUT}) ..."
        sleep 1
        _timeout="$((_timeout + 1))"
    done
    echo "socket found, clamd started."

    echo "Starting Freshclamd"
    freshclam \
                --checks="${FRESHCLAM_CHECKS:-1}" \
                --daemon \
                --foreground \
                --stdout \
                --user="clamav" \
                &

}

start_e2guard()
{
    echo "Starting e2guardian"
    # To support clamav content scan
    # addgroup clamav e2guard
    chown -R clamav:clamav /var/log/e2guardian
    exec e2guardian
}

run() {
	prepare_folders
	create_cert
    start_clamav
	start_e2guard
}

run

exit 0
