FROM alpine:3.15

# Install packages
RUN apk -U --no-cache add \
    dumb-init \
    logrotate \
    suricata && \
    rm -rf /tmp/* && \
    rm -rf /var/cache/apk/* && \
    rm /etc/logrotate.d/* && \
    sed -i '/main log file/d' /etc/logrotate.conf && \
    sed -i '/\/var\/log\/messages/d' /etc/logrotate.conf

COPY start.sh /
COPY /suricata.logrotate /etc/logrotate.d/suricata
COPY suricata-update.sh /etc/suricata/suricata-update.sh
COPY suricata-cronjobs /etc/crontabs/suricata-cronjobs
COPY suricata.yaml /etc/suricata/suricata.yaml
RUN chmod 755 /start.sh && chmod +x /etc/crontabs/suricata-cronjobs

ENTRYPOINT ["/start.sh"]
CMD ["suricata","-i","eth0"]