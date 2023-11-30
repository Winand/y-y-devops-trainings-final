# base-debian12 image also contains libc, libssl
# https://github.com/GoogleContainerTools/distroless/blob/main/base/README.md
# FROM gcr.io/distroless/static-debian12:latest-amd64
FROM debian:10-slim

ARG EMAIL
ARG PG_HOST
ARG DB_PASSWORD
ARG LOGDIR
ARG PORT_INTERNAL

ADD https://storage.yandexcloud.net/final-homework/bingo /opt/bingo/
ADD config.yaml /opt/bingo/

RUN useradd app && \
    chmod +x /opt/bingo/bingo && \
    sed /opt/bingo/config.yaml -i \
        -e "s/\${EMAIL}/${EMAIL?}/g" \
        -e "s/\${PG_HOST}/${PG_HOST?}/g" \
        -e "s/\${DB_PASSWORD}/${DB_PASSWORD?}/g" && \
    chown app:app /opt/bingo/config.yaml && \
    mkdir -p /opt/bongo/logs/${LOGDIR?} && chown app:app /opt/bongo/logs/${LOGDIR?}

USER app
ENTRYPOINT [ "/opt/bingo/bingo" ]
# https://stackoverflow.com/a/22150099
EXPOSE ${PORT_INTERNAL}
