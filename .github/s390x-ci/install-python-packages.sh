#!/usr/bin/env bash

set -euxo pipefail

: "${PYTORCH_VERSION:?PYTORCH_VERSION must be set}"
: "${PYTORCH_INDEX_URL:?PYTORCH_INDEX_URL must be set}"

requirements=(
    -r /tmp/requirements/requirements.txt
    -r /tmp/requirements/test-requirements.txt
    -r /tmp/requirements/tutorials-requirements.txt
)

# Install into the system Python, as the AMD CI image does
# (PIP_BREAK_SYSTEM_PACKAGES=1), from the wheels built in the wheels stage.
python3 -m pip install --no-cache-dir --no-index --find-links /wheelhouse "${requirements[@]}"

python3 -m pip install --no-cache-dir --index-url "${PYTORCH_INDEX_URL}" "torch==${PYTORCH_VERSION}"

# CI-only: the s390x jobs run pytest with --timeout so that one slow compile
# cannot use up the job's time limit. The wheel is pure Python.
python3 -m pip install --no-cache-dir "pytest-timeout==2.4.0"

python3 - <<'PY'
import importlib.metadata
import os

import hatchet
import matplotlib
import numpy
import pandas
import pytest_timeout
import scipy
import torch

expected = os.environ["PYTORCH_VERSION"]
actual = importlib.metadata.version("torch")
if actual != expected:
    raise SystemExit(f"installed torch=={actual}, expected torch=={expected}")
for module in (torch, numpy, scipy, pandas, matplotlib, hatchet):
    print(f"{module.__name__}: {getattr(module, '__version__', 'unknown')}")
PY

# Uninstall any triton that came in as a dependency.
python3 -m pip uninstall -y triton pytorch-triton || true
python3 -m pip freeze > /wheelhouse/MANIFEST.txt

# Confirm the image does not retain a packaged Triton, which would shadow
# the source checkout installed by CI.
! python3 -c 'import triton'
