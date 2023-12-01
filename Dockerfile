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

# base-debian12 image also contains libc, libssl
# https://github.com/GoogleContainerTools/distroless/blob/main/base/README.md
# chown https://github.com/GoogleContainerTools/distroless/issues/427
# chmod https://stackoverflow.com/questions/73838366/google-distroless-image-chmod-not-found
# user=nonroot https://stackoverflow.com/q/73568034
FROM gcr.io/distroless/static-debian12:latest-amd64

ARG PORT_INTERNAL

COPY --from=builder --chown=nonroot:nonroot /opt /opt
ADD --chown=nonroot:nonroot --chmod=100 \
    https://storage.yandexcloud.net/final-homework/bingo /opt/bingo/

USER nonroot
ENTRYPOINT [ "/opt/bingo/bingo" ]
# https://stackoverflow.com/a/22150099
EXPOSE ${PORT_INTERNAL?}
