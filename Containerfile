FROM alpine:3.19 AS nginx

ARG NGINX_HOSTNAME=localhost
ARG NGINX_HTTP_PORT=80

RUN apk update && apk upgrade && apk add \
    nginx          \
    nginx-mod-mail \
    envsubst

COPY nginx /etc/nginx
RUN envsubst '$NGINX_HOSTNAME:$NGINX_HTTP_PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

EXPOSE ${NGINX_HTTP_PORT}

ENTRYPOINT ["/usr/sbin/nginx", "-g", "daemon off;"]

