FROM --platform=linux/amd64 debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bc bison flex cpio gzip git                  \
    libelf-dev libssl-dev                                        \
    qemu-system-x86                                              \
    python3 python3-venv python3-pip                             \
    curl wget ca-certificates                                    \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
