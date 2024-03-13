FROM alpine:3.19 AS build
RUN apk add \
	clang \
	make \
	;

ADD . /tcp_server

RUN make -C /tcp_server CC='clang -static'

FROM scratch AS tcp_server
COPY --from=build /tcp_server/tcp_server /usr/local/bin/tcp_server
