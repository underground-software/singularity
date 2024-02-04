FROM alpine:3.19 AS nginx

RUN apk update && apk upgrade && apk add \
    nginx          \
    nginx-mod-mail

EXPOSE 80

ENTRYPOINT ["/usr/sbin/nginx", "-g", "daemon off;"]

