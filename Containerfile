FROM fedora:latest AS build
RUN dnf -y update
RUN dnf -y install \
	git \
	musl-clang \
	musl-libc-static \
	make \
	;

ADD . /pop

RUN git -C /pop submodule update --init --recursive

RUN make -C /pop/tcp_server CC='musl-clang -static'

RUN make -C /pop CC='musl-clang -static'

RUN mkdir -p /mnt/mail

#FROM fedora:latest as smtp
#RUN dnf -y update && dnf -y install libselinux-utils && dnf clean all
FROM scratch as pop
COPY --from=build /mnt/mail /mnt/mail
VOLUME /mnt/mail
COPY --from=build /pop/tcp_server/tcp_server /usr/local/bin/tcp_server
COPY --from=build /pop/pop3 /usr/local/bin/pop3

EXPOSE 995
ENTRYPOINT ["/usr/local/bin/tcp_server", "-p", "995", "/usr/local/bin/pop3", "pop3", "/mnt/mail"]
