# rust builder
FROM docker.io/library/rust:1.52 as builder
RUN apt-get -y -qq update && apt-get -y -qq install jq
WORKDIR /usr/local/src/ghost
COPY . /usr/local/src/ghost
RUN make build-prep-version-file

# debian buster
FROM docker.io/library/debian:10.9
COPY --from=builder /usr/local/src/ghost/target/release/ghost /usr/local/bin
COPY --from=builder /usr/local/src/ghost/target/meta.version /usr/local/etc/ghost-release
CMD ["/usr/local/bin/ghost"]
EXPOSE 8000
ENV RUST_LOG=info
