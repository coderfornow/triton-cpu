#!/usr/bin/env bash

set -euxo pipefail

: "${PYTORCH_VERSION:?PYTORCH_VERSION must be set}"
: "${PYTORCH_INDEX_URL:?PYTORCH_INDEX_URL must be set}"

requirements=(
    -r /tmp/requirements/requirements.txt
    -r /tmp/requirements/test-requirements.txt
    -r /tmp/requirements/tutorials-requirements.txt
)

python3 -m venv /opt/venv
export PATH=/opt/venv/bin:${PATH}
python3 -m pip install --no-cache-dir --upgrade pip

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
# constrains the tutorials list, then install from the wheelhouse only.
python3 -m pip wheel --no-cache-dir --wheel-dir /wheelhouse "${requirements[@]}"
python3 -m pip install --no-cache-dir --no-index "${requirements[@]}"

python3 -m pip install --no-cache-dir --index-url "${PYTORCH_INDEX_URL}" "torch==${PYTORCH_VERSION}"

python3 - <<'PY'
import importlib.metadata
import os

import hatchet
import matplotlib
import numpy
import pandas
import scipy
import torch

expected = os.environ["PYTORCH_VERSION"]
actual = importlib.metadata.version("torch")
if actual != expected:
    raise SystemExit(f"installed torch=={actual}, expected torch=={expected}")
for module in (torch, numpy, scipy, pandas, matplotlib):
    print(f"{module.__name__}: {module.__version__}")
PY

# Uninstall any triton that came in as a dependency.
python3 -m pip uninstall -y triton pytorch-triton || true
python3 -m pip freeze > /wheelhouse/MANIFEST.txt

# Confirm the image does not retain a packaged Triton, which would shadow
# the source checkout installed by CI.
! python3 -c 'import triton'
