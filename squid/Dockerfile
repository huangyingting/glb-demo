FROM alpine:3.12

LABEL maintainer="huangyingting@outlook.com"

#set enviromental values for certificate CA generation
ENV CN=squid.local \
    OU=Squid \
    O=Squid-Proxy \
    L=Shanghai \
    ST=Shanghai \
    C=CN \
    DEBUG_LEVEL=5 \
    LOCAL_NET=

COPY start.sh /

RUN apk add --no-cache \
    squid \
    openssl \
    dumb-init \
    ca-certificates && \
    update-ca-certificates && \
    cp /etc/ssl/openssl.cnf.dist /etc/ssl/openssl.cnf && \
    chmod +x /start.sh

COPY squid.conf /etc/squid/

EXPOSE 3128
EXPOSE 3138
EXPOSE 3148

WORKDIR /
ENTRYPOINT ["dumb-init", "--"]
CMD ["sh", "start.sh"]