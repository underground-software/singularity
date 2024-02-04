FROM alpine:3.19 AS nginx

RUN apk update && apk upgrade && apk add \
    nginx          \
    nginx-mod-mail

COPY nginx /etc/nginx

EXPOSE 80

ENTRYPOINT ["/usr/sbin/nginx", "-g", "daemon off;"]

