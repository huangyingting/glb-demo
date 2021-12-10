FROM alpine:3.15

# Install packages
RUN apk -U --no-cache add \
    dumb-init \
    suricata && \
    rm -rf /tmp/* && \
    rm -rf /var/cache/apk/* && \
    ln -sf /dev/stdout /var/log/suricata/eve.log

COPY start.sh /
COPY suricata-update.sh /etc/suricata/suricata-update.sh
COPY suricata-update-cron /etc/crontabs/suricata-update-cron
RUN chmod 755 /start.sh && chmod +x /etc/crontabs/suricata-update-cron
 
ENTRYPOINT ["/start.sh"]
CMD ["suricata","-i","eth0"]