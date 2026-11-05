#!/usr/bin/env bash

set -euxo pipefail

requirements=(
    -r /tmp/requirements/requirements.txt
    -r /tmp/requirements/test-requirements.txt
    -r /tmp/requirements/tutorials-requirements.txt
)

# PyPI publishes no s390x wheel for these packages, so build them from sdists.
# Build in dependency order and let every isolated build environment find the
# wheels built so far; otherwise pandas, scipy and matplotlib each rebuild
# numpy from source. Pin pandas here because the tutorials list leaves it open.
mkdir -p /wheelhouse
export PIP_FIND_LINKS=/wheelhouse
source_builds=(
    numpy
    "markupsafe msgpack pillow"
    "pandas<3.0 scipy matplotlib"
    llnl-hatchet
)
for group in "${source_builds[@]}"; do
    read -r -a packages <<< "${group}"
    python3 -m pip wheel --no-cache-dir --wheel-dir /wheelhouse "${packages[@]}"
done

# Resolve all three requirement files together so the pandas<3.0 pin also
# constrains the tutorials list. The final stage installs from /wheelhouse.
python3 -m pip wheel --no-cache-dir --wheel-dir /wheelhouse "${requirements[@]}"
