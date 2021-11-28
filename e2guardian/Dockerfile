FROM alpine:3.15

LABEL maintainer="huangyingting@outlook.com"

#set enviromental values for certificate CA generation
ENV CN=e2guardian.local \
    OU=e2guardian \
    O=e2guardian \
    L=Shanghai \
    ST=Shanghai \
    C=CN

RUN apk add --no-cache \
    e2guardian \
    openssl \
    dumb-init \
    ca-certificates && \
    update-ca-certificates

COPY start.sh /
COPY e2guardian.conf /etc/e2guardian/

EXPOSE 8080
EXPOSE 8443

WORKDIR /
ENTRYPOINT ["dumb-init", "--"]
CMD ["sh", "start.sh"]