#!/usr/bin/env bash

set -euxo pipefail

: "${JSON_VERSION:?JSON_VERSION must be set}"
: "${SLEEF_COMMIT:?SLEEF_COMMIT must be set}"

# TRITON_OFFLINE_BUILD stops the build from downloading these, so provide the
# pinned versions here (JSON_SYSPATH and TRITON_SLEEF_SOURCE_DIR).
tmp="$(mktemp -d)"
curl --fail --location --silent --show-error --output "${tmp}/include.zip" \
    "https://github.com/nlohmann/json/releases/download/${JSON_VERSION}/include.zip"
mkdir -p /opt/json
unzip -q "${tmp}/include.zip" -d /opt/json
test -f /opt/json/include/nlohmann/json.hpp
rm -rf "${tmp}"

git init /opt/sleef
git -C /opt/sleef remote add origin https://github.com/shibatch/sleef.git
git -C /opt/sleef fetch --depth 1 origin "${SLEEF_COMMIT}"
git -C /opt/sleef checkout --detach FETCH_HEAD
rm -rf /opt/sleef/.git
