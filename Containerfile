FROM fedora:latest

RUN dnf update -y && \
	dnf install -y \
	podman \
	fuse-overlayfs \
	podman-compose \
	jq \
	ShellCheck \
	which \
	python-flake8 \
	python-virtualenv \
	python-pip \
	socat \
	git \
	git-email

# needed because for some reason newuidmap and newgidmap programs
# lose their xattrs giving them caps when the container image for
# fedora is created, without this, we see the following output:
# $ rpm -V shadow-utils
# ........P    /usr/bin/newgidmap
# ........P    /usr/bin/newuidmap
RUN rpm --setcaps shadow-utils

RUN useradd podman; \
echo podman:10000:5000 > /etc/subuid; \
echo podman:10000:5000 > /etc/subgid;

RUN sed -i 's/log_driver = "journald"/log_driver = "json-file"/' /usr/share/containers/containers.conf && \
	mkdir /run/storage && \
	mkdir -p /home/podman/.local/share/containers && \
	ln -s /run/storage /home/podman/.local/share/containers/storage && \
	:

WORKDIR /home/podman

COPY --from=singularity_git_repo . ./singularity

COPY start.sh .

RUN chown -R podman:podman ./singularity

USER podman:podman

WORKDIR singularity

ENTRYPOINT ["./start.sh"]
