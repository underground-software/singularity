FROM alpine:3.19 AS build

RUN apk update && apk upgrade && apk add \
    envsubst

COPY nginx.conf.template .

ARG NGINX_HOSTNAME=localhost
ARG NGINX_HTTP_PORT=80
ARG NGINX_HTTPS_PORT=443
ARG NGINX_SMTPS_PORT=465
ARG NGINX_POP3S_PORT=995

RUN envsubst '$NGINX_HOSTNAME:$NGINX_HTTP_PORT:$NGINX_HTTPS_PORT:$NGINX_SMTPS_PORT:$NGINX_POP3S_PORT' < nginx.conf.template > nginx.conf

FROM alpine:3.19 AS nginx

RUN apk update && apk upgrade && apk add \
    nginx          \
    nginx-mod-mail

COPY --from=build nginx.conf /etc/nginx/

VOLUME /etc/ssl/nginx

ARG NGINX_HTTP_PORT
ARG NGINX_HTTPS_PORT
ARG NGINX_SMTPS_PORT
ARG NGINX_POP3S_PORT
EXPOSE ${NGINX_HTTP_PORT}
EXPOSE ${NGINX_HTTPS_PORT}
EXPOSE ${NGINX_SMTPS_PORT}
EXPOSE ${NGINX_POP3S_PORT}

ENTRYPOINT ["/usr/sbin/nginx", "-g", "daemon off;"]

