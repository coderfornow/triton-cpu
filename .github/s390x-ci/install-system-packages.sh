#!/usr/bin/env bash

set -euxo pipefail

# The same base toolchain as .github/amd-ci (clang, lld, ccache), plus what the
# s390x source builds need: Fortran and OpenBLAS for scipy, image and font
# libraries for pillow and matplotlib, and the LLVM build's optional deps.
# Ubuntu has no libomp-dev for s390x; install-llvm.sh builds libomp instead.
packages=(
    build-essential
    ca-certificates
    ccache
    clang
    cmake
    curl
    file
    gfortran
    git
    jq
    libedit-dev
    libffi-dev
    libfreetype-dev
    libjpeg-turbo8-dev
    liblcms2-dev
    libopenblas-dev
    libpng-dev
    libtiff-dev
    libwebp-dev
    libxml2-dev
    lld
    ninja-build
    pkg-config
    python3-dev
    python3-pip
    python3-venv
    unzip
    xz-utils
    zip
    zlib1g-dev
)

apt-get update
apt-get install -y --no-install-recommends "${packages[@]}"
rm -rf /var/lib/apt/lists/*
