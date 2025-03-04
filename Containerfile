FROM fedora:latest

RUN dnf update -y && \
	dnf install -y \
	podman \
	podman-compose \
	jq \
	ShellCheck \
	which \
	python-flake8 \
	python-virtualenv \
	python-pip \
	git

RUN sed -i 's/log_driver = "journald"/log_driver = "json-file"/' /usr/share/containers/containers.conf && \
	mkdir /run/storage && \
	ln -s /run/storage /var/lib/containers/storage && \
	:

COPY --from=singularity_git_repo . ./singularity

COPY start.sh .

WORKDIR singularity

ENTRYPOINT ["/start.sh"]
