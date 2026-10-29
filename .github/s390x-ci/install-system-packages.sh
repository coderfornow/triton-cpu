#!/usr/bin/env bash

set -euxo pipefail

# Every package comes from the public UBI 10 repositories, so no subscription
# is needed. ninja-build and openblas-devel live in CodeReady Builder, which
# UBI 10 enables by default.
packages=(
    clang
    cmake
    file
    freetype-devel
    gcc
    gcc-c++
    gcc-gfortran
    git
    jq
    lcms2-devel
    libedit-devel
    libffi-devel
    libgomp
    libjpeg-turbo-devel
    libpng-devel
    libtiff-devel
    libwebp-devel
    libxml2-devel
    make
    ninja-build
    openblas-devel
    pkgconf-pkg-config
    python3
    python3-devel
    python3-pip
    tar
    unzip
    which
    xz
    zlib-ng-compat-devel
)

dnf install -y --setopt=install_weak_deps=False "${packages[@]}"
dnf clean all
rm -rf /var/cache/dnf
