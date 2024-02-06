FROM alpine:3.19 AS nginx

ARG NGINX_HOSTNAME=localhost
ARG NGINX_HTTP_PORT=80
ARG NGINX_HTTPS_PORT=443
ARG NGINX_SMTPS_PORT=465
ARG NGINX_POP3S_PORT=995

RUN apk update && apk upgrade && apk add \
    nginx          \
    nginx-mod-mail \
    envsubst

COPY nginx.conf.template /etc/nginx/
RUN envsubst '$NGINX_HOSTNAME:$NGINX_HTTP_PORT:$NGINX_HTTPS_PORT:$NGINX_SMTPS_PORT:$NGINX_POP3S_PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

VOLUME /etc/ssl/nginx

EXPOSE ${NGINX_HTTP_PORT}
EXPOSE ${NGINX_HTTPS_PORT}
EXPOSE ${NGINX_SMTPS_PORT}
EXPOSE ${NGINX_POP3S_PORT}

ENTRYPOINT ["/usr/sbin/nginx", "-g", "daemon off;"]

