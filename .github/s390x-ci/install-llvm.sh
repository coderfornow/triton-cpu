#!/usr/bin/env bash

set -euxo pipefail

: "${LLVM_COMMIT_HASH:?LLVM_COMMIT_HASH must be set}"

export LLVM_COMMIT_HASH
export LLVM_PROJECT_PATH=/tmp/llvm-project
export LLVM_BUILD_PATH="${LLVM_PROJECT_PATH}/build"
export LLVM_INSTALL_PATH=/opt/llvm
export LLVM_BUILD_TYPE=Release

# Fetch only the pinned commit. build-llvm-project.sh would otherwise clone the
# full history; given an existing checkout it just fetches and resets.
git init "${LLVM_PROJECT_PATH}"
git -C "${LLVM_PROJECT_PATH}" remote add origin https://github.com/llvm/llvm-project
git -C "${LLVM_PROJECT_PATH}" fetch --depth 1 origin "${LLVM_COMMIT_HASH}"
git -C "${LLVM_PROJECT_PATH}" checkout --detach FETCH_HEAD

# Configure and build with the same flags Triton developers use. The default
# targets Native;NVPTX;AMDGPU resolve Native to SystemZ; libtriton links the
# NVPTX and AMDGPU code generators unconditionally.
build-llvm-project.sh
ninja -C "${LLVM_BUILD_PATH}" install-distribution

# Check the pieces Triton's CMake and lit tests look for.
for tool in FileCheck clang++ llc llvm-config mlir-tblgen not opt; do
    test -x "${LLVM_INSTALL_PATH}/bin/${tool}"
done
test -d "${LLVM_INSTALL_PATH}/lib/cmake/mlir"
test -d "${LLVM_INSTALL_PATH}/lib/cmake/lld"
targets="$("${LLVM_INSTALL_PATH}/bin/llvm-config" --targets-built)"
for target in SystemZ NVPTX AMDGPU; do
    [[ " ${targets} " == *" ${target} "* ]]
done

rm -rf "${LLVM_PROJECT_PATH}"
