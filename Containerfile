ARG BASE_IMAGE

# rust builder
FROM docker.io/library/rust:1.72 as builder
ARG TARGET
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get -y -qq update && apt-get -y -qq install jq
RUN rustup target add $TARGET
WORKDIR /usr/local/src/ghost
COPY . /usr/local/src/ghost
RUN TARGET=$TARGET make build-prep

# app
FROM $BASE_IMAGE
ARG TARGET
COPY --from=builder /usr/local/src/ghost/target/$TARGET/release/ghost /usr/local/bin/ghost
COPY --from=builder /usr/local/src/ghost/target/meta.version /usr/local/etc/ghost-release
COPY --from=builder /usr/local/src/ghost/target/meta.version /usr/local/share/ghost/static/meta.txt
CMD ["/usr/local/bin/ghost"]
EXPOSE 8000
ENV RUST_LOG=info
ENV GHOST_STATIC_DIR=/usr/local/share/ghost/static
