FROM alpine:3.15

LABEL maintainer="huangyingting@outlook.com"

#set enviromental values for certificate CA generation
ENV CN=e2guardian.local \
    OU=e2guardian \
    O=e2guardian \
    L=Shanghai \
    ST=Shanghai \
    C=CN

RUN apk add --no-cache openssl dumb-init ca-certificates e2guardian clamav && \
    update-ca-certificates && \
    freshclam --foreground --stdout

COPY start.sh /
COPY e2guardian.conf /etc/e2guardian/
COPY e2guardianf1.conf /etc/e2guardian/
COPY clamdscan.conf /etc/e2guardian/contentscanners/

EXPOSE 8080
EXPOSE 8443

WORKDIR /
ENTRYPOINT ["dumb-init", "--"]
CMD ["sh", "start.sh"]