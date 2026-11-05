#!/usr/bin/env bash

set -euxo pipefail

: "${LLVM_COMMIT_HASH:?LLVM_COMMIT_HASH must be set}"

export LLVM_COMMIT_HASH
export LLVM_PROJECT_PATH=/tmp/llvm-project
export LLVM_BUILD_PATH="${LLVM_PROJECT_PATH}/build"
export LLVM_INSTALL_PATH=/opt/llvm
export LLVM_BUILD_TYPE=Release
# Build with the distribution clang and lld, as AMD CI builds Triton.
export TRITON_BUILD_WITH_CLANG_LLD=1

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

# Ubuntu packages no LLVM OpenMP runtime for s390x, but upstream supports and
# tests it there (the openmp-s390x-linux buildbot). Build libomp from the same
# commit with the just-built clang, as a runtimes build against this LLVM tree,
# so that /opt/llvm/bin/clang -fopenmp finds omp.h and libomp. This counts as
# a standalone runtimes build, which installs headers to CMAKE_INSTALL_INCLUDEDIR,
# so point that at clang's resource directory. The library goes to the
# per-target directory /opt/llvm/lib/<triple>, which clang searches; the
# Dockerfile registers that directory with the dynamic loader.
OPENMP_BUILD_PATH="${LLVM_PROJECT_PATH}/build-openmp"
CLANG_RESOURCE_DIR="$("${LLVM_INSTALL_PATH}/bin/clang" -print-resource-dir)"
OPENMP_LIB_PATH="${LLVM_INSTALL_PATH}/lib/$("${LLVM_INSTALL_PATH}/bin/clang" -print-target-triple)"
cmake -G Ninja -S "${LLVM_PROJECT_PATH}/runtimes" -B "${OPENMP_BUILD_PATH}" \
    -DCMAKE_BUILD_TYPE="${LLVM_BUILD_TYPE}" \
    -DCMAKE_C_COMPILER="${LLVM_BUILD_PATH}/bin/clang" \
    -DCMAKE_CXX_COMPILER="${LLVM_BUILD_PATH}/bin/clang++" \
    -DCMAKE_INSTALL_PREFIX="${LLVM_INSTALL_PATH}" \
    -DCMAKE_INSTALL_INCLUDEDIR="${CLANG_RESOURCE_DIR}/include" \
    -DLLVM_BINARY_DIR="${LLVM_BUILD_PATH}" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DLLVM_ENABLE_RUNTIMES=openmp \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLIBOMP_INSTALL_ALIASES=OFF \
    -DLIBOMP_OMPD_SUPPORT=OFF
ninja -C "${OPENMP_BUILD_PATH}" install
test -f "${OPENMP_LIB_PATH}/libomp.so"

# Check that the pinned clang builds and runs an OpenMP program with it.
cat > /tmp/omp-check.c <<'EOF'
#include <omp.h>
#include <stdio.h>
int main(void) {
    int threads = 0;
#pragma omp parallel
#pragma omp atomic
    threads++;
    printf("libomp threads: %d\n", threads);
    return threads == 4 ? 0 : 1;
}
EOF
"${LLVM_INSTALL_PATH}/bin/clang" -fopenmp /tmp/omp-check.c -o /tmp/omp-check
OMP_NUM_THREADS=4 LD_LIBRARY_PATH="${OPENMP_LIB_PATH}" /tmp/omp-check
LD_LIBRARY_PATH="${OPENMP_LIB_PATH}" ldd /tmp/omp-check | grep -q "${OPENMP_LIB_PATH}/libomp.so"
rm -f /tmp/omp-check /tmp/omp-check.c

# CI compares this with cmake/llvm-info.json to catch a stale image.
echo "${LLVM_COMMIT_HASH}" > "${LLVM_INSTALL_PATH}/llvm-commit"

rm -rf "${LLVM_PROJECT_PATH}"
