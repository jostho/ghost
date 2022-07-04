# rust builder
FROM docker.io/library/rust:1.61 as builder
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get -y -qq update && apt-get -y -qq install jq
WORKDIR /usr/local/src/ghost
COPY . /usr/local/src/ghost
RUN make build-prep

# debian
FROM docker.io/library/debian:11
COPY --from=builder /usr/local/src/ghost/target/release/ghost /usr/local/bin
COPY --from=builder /usr/local/src/ghost/target/meta.version /usr/local/etc/ghost-release
COPY --from=builder /usr/local/src/ghost/target/meta.version /usr/local/share/ghost/static/meta.txt
CMD ["/usr/local/bin/ghost"]
EXPOSE 8000
ENV RUST_LOG=info
ENV GHOST_STATIC_DIR=/usr/local/share/ghost/static
