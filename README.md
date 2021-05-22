# Ghost

![CI](https://github.com/jostho/ghost/workflows/CI/badge.svg)

This is an echo server written in rust using [warp](https://github.com/seanmonstar/warp).
This can be used to simulate http responses.

## Environment

* fedora 34
* rustup 1.24
* rust 1.52
* make 4.3

## Build

To build or run, use `cargo`

    cargo build
    cargo run

## Image

A `Makefile` is provided to build a container image

Check prerequisites to build the image

    make check

To build the default container image

    make image

To run the container image - use `podman`

    podman run -d -p 8000:8000 <imageid>
