# syntax=docker/dockerfile:1

# Build using the `build.py` script. It records complete argument sets for the
# images used in CI and derives the LLVM, JSON and SLEEF pins from the repo.
#
# The llvm and wheels stages are independent; build with `--jobs 2` so they
# run in parallel.

ARG BASE_IMAGE=ubuntu:26.04

FROM ${BASE_IMAGE} AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_BREAK_SYSTEM_PACKAGES=1

COPY --chmod=0755 .github/s390x-ci/install-system-packages.sh /usr/local/bin/
RUN install-system-packages.sh

# There is no prebuilt LLVM for s390x, so build the pinned commit from source.
FROM base AS llvm

ARG LLVM_COMMIT_HASH

COPY --chmod=0755 scripts/build-llvm-project.sh /usr/local/bin/
COPY --chmod=0755 .github/s390x-ci/install-llvm.sh /usr/local/bin/
RUN install-llvm.sh

# Several Python dependencies have no s390x wheel on PyPI, so build them into
# a wheelhouse.
FROM base AS wheels

COPY python/requirements.txt /tmp/requirements/requirements.txt
COPY python/test-requirements.txt /tmp/requirements/test-requirements.txt
COPY python/tutorials/requirements.txt /tmp/requirements/tutorials-requirements.txt
COPY --chmod=0755 .github/s390x-ci/build-python-wheels.sh /usr/local/bin/
RUN build-python-wheels.sh

FROM base

ARG LLVM_COMMIT_HASH
ARG JSON_VERSION
ARG SLEEF_COMMIT
ARG PYTORCH_VERSION
ARG PYTORCH_INDEX_URL

LABEL org.opencontainers.image.title="Triton CPU s390x CI image"
LABEL org.opencontainers.image.description="LLVM, PyTorch, and OS dependencies for Triton CPU CI on s390x"
LABEL org.opencontainers.image.source="https://github.com/triton-lang/triton-cpu"
LABEL org.opencontainers.image.version="llvm${LLVM_COMMIT_HASH}-pytorch${PYTORCH_VERSION}"
LABEL org.triton-lang.image.llvm.commit="${LLVM_COMMIT_HASH}"
LABEL org.triton-lang.image.json.version="${JSON_VERSION}"
LABEL org.triton-lang.image.sleef.commit="${SLEEF_COMMIT}"
LABEL org.triton-lang.image.pytorch.version="${PYTORCH_VERSION}"

COPY --chmod=0755 .github/s390x-ci/install-thirdparty-sources.sh /usr/local/bin/
RUN install-thirdparty-sources.sh

COPY --from=llvm /opt/llvm /opt/llvm
# Let programs built with -fopenmp find libomp (see install-llvm.sh). Register
# only the per-target directory, which holds libomp alone, not /opt/llvm/lib.
RUN echo "/opt/llvm/lib/$(/opt/llvm/bin/clang -print-target-triple)" > /etc/ld.so.conf.d/llvm-libomp.conf \
    && ldconfig \
    && ldconfig -p | grep -q "libomp.so .*/opt/llvm/lib/"
COPY --from=wheels /wheelhouse /wheelhouse

COPY python/requirements.txt /tmp/requirements/requirements.txt
COPY python/test-requirements.txt /tmp/requirements/test-requirements.txt
COPY python/tutorials/requirements.txt /tmp/requirements/tutorials-requirements.txt
COPY --chmod=0755 .github/s390x-ci/install-python-packages.sh /usr/local/bin/
RUN install-python-packages.sh

# The NVIDIA toolchain has no linux-s390x download, so build offline against
# the LLVM, JSON and SLEEF trees above. Proton needs CUPTI, so disable it.
ENV LLVM_SYSPATH=/opt/llvm
ENV JSON_SYSPATH=/opt/json
ENV TRITON_SLEEF_SOURCE_DIR=/opt/sleef
ENV TRITON_OFFLINE_BUILD=1
ENV TRITON_BUILD_PROTON=OFF
ENV TRITON_DEFAULT_BACKEND=cpu
# CI builds Triton with the distribution clang and lld
# (TRITON_BUILD_WITH_CLANG_LLD), as the AMD CI does. At run time the CPU
# backend builds its launcher with -fopenmp and assembles kernels with CC. Use
# the pinned clang there: it matches the LLVM that generates the assembly, and
# install-llvm.sh gives it libomp, which Ubuntu does not package for s390x.
ENV CC=/opt/llvm/bin/clang
ENV CXX=/opt/llvm/bin/clang++

CMD ["/bin/bash"]
