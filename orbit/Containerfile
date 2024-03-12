FROM alpine:3.19 AS build

RUN apk update && apk upgrade && apk add \
	python3-dev \
	py3-pip \
	sqlite \
	build-base \
	libffi-dev

COPY requirements.txt /requirements.txt
RUN python3 -m venv /radius-venv && \
	source /radius-venv/bin/activate && \
	pip install -r requirements.txt

COPY . /orbit
WORKDIR /orbit

RUN sqlite3 orbit.db ".read init-db.sql"

FROM alpine:3.19 AS orbit

RUN apk update && apk upgrade && apk add \
	python3 \
	cgit

COPY --from=build /orbit /orbit
COPY --from=build /radius-venv /radius-venv

RUN mkdir /var/git
VOLUME /var/git

COPY cgitrc /etc/cgitrc

EXPOSE 9098

CMD /bin/sh -c "source /radius-venv/bin/activate && uwsgi /orbit/radius.ini"
