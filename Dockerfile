FROM debian:10-slim as builder

ARG EMAIL
ARG PG_HOST
ARG PG_PORT
ARG DB_PASSWORD
ARG LOGDIR

ADD config.yaml /opt/bingo/
RUN sed /opt/bingo/config.yaml -i \
        -e "s/\${EMAIL}/${EMAIL?}/g" \
        -e "s/\${PG_HOST}/${PG_HOST?}/g" \
        -e "s/\${PG_PORT}/${PG_PORT:-5432}/g" \
        -e "s/\${DB_PASSWORD}/${DB_PASSWORD?}/g" && \
    mkdir -p /opt/bongo/logs/${LOGDIR?} && \
    ln -s /dev/null /opt/bongo/logs/${LOGDIR?}/main.log
# Note: failed to use ADD because of download timeout
RUN apt update && apt install wget -y && \
    wget -O /wget https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox_WGET && \
    wget -O /kill https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox_KILL && \
    wget -O /sh https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox_SH_IS_ASH

# base-debian12 image also contains libc, libssl
# https://github.com/GoogleContainerTools/distroless/blob/main/base/README.md
# chown https://github.com/GoogleContainerTools/distroless/issues/427
# chmod https://stackoverflow.com/questions/73838366/google-distroless-image-chmod-not-found
# user=nonroot https://stackoverflow.com/q/73568034
FROM gcr.io/distroless/static-debian12:latest-amd64

ARG PORT_INTERNAL
ENV PORT_INTERNAL=${PORT_INTERNAL?}

COPY --from=builder --chown=nonroot:nonroot /opt /opt
ADD --chown=nonroot:nonroot --chmod=100 \
    https://storage.yandexcloud.net/final-homework/bingo /opt/bingo/
COPY --from=builder --chown=nonroot:nonroot --chmod=100 /wget /usr/bin/wget
COPY --from=builder --chown=nonroot:nonroot --chmod=100 /kill /usr/bin/kill
COPY --from=builder --chown=nonroot:nonroot --chmod=100 /sh /bin/sh

USER nonroot
ENTRYPOINT [ "/opt/bingo/bingo" ]
# https://stackoverflow.com/a/22150099
EXPOSE ${PORT_INTERNAL?}

# Проверка состояния приложения
# https://github.com/GoogleContainerTools/distroless/issues/183#issuecomment-571723446
# https://community.zenduty.com/t/how-to-run-a-healthcheck-using-wget-or-curl-on-a-grafana-grafana-master-image-in-a-container/659/10
# Variable expansion requires a shell https://stackoverflow.com/a/76100442
HEALTHCHECK --interval=25s \
    CMD wget -qt1 -O- http://localhost:${PORT_INTERNAL?}/ping || kill 1
