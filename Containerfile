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
	gawk \
	socat \
	git \
	git-email

RUN sed -i 's/log_driver = "journald"/log_driver = "json-file"/' /usr/share/containers/containers.conf

COPY --from=singularity_git_repo . ./singularity

RUN mkdir -p singularity/{repos,docs}

COPY start.sh .

WORKDIR singularity

ENTRYPOINT ["/start.sh"]
