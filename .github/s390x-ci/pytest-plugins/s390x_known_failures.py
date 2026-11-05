"""Mark the tests listed in known-failures.txt for the s390x CI jobs.

Load with ``-p s390x_known_failures`` and ``.github/s390x-ci/pytest-plugins`` on
PYTHONPATH (not ``.github/s390x-ci``, whose build.py would shadow PyPA build).

Each entry in known-failures.txt is ``skip <node id>`` or ``xfail <node id>``.
An entry without a ``[...]`` parameter part covers every parametrization of
that test. A ``# ...`` comment line gives the reason for the entries below it,
up to the next comment or blank line.

- ``skip`` is for tests that crash the worker or exceed the timeout.
- ``xfail`` (strict=False) is for tests that fail cleanly. A fix PR then shows
  them as XPASS, and the fix PR removes their entries.

The tests are marked rather than deselected, so the report still lists them
and python/test/conftest.py still sees every allowlisted test_core test.
"""

from pathlib import Path

import pytest

KNOWN_FAILURES = Path(__file__).parents[1] / "known-failures.txt"
MODES = ("skip", "xfail")


def _load(path):
    entries = {}
    default = reason = "known s390x failure"
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line:
            reason = default
            continue
        if line.startswith("#"):
            reason = line.lstrip("#").strip() or reason
            continue
        mode, _, node_id = line.partition(" ")
        node_id = node_id.strip()
        if mode not in MODES or not node_id:
            raise pytest.UsageError(f"{path}:{lineno}: expected 'skip|xfail <node id>', got {raw!r}")
        if node_id in entries:
            raise pytest.UsageError(f"{path}:{lineno}: duplicate entry {node_id}")
        entries[node_id] = (mode, reason)
    return entries


@pytest.hookimpl(trylast=True)
def pytest_collection_modifyitems(items):
    entries = _load(KNOWN_FAILURES)
    for item in items:
        key = item.nodeid if item.nodeid in entries else item.nodeid.split("[", 1)[0]
        if key not in entries:
            continue
        mode, reason = entries[key]
        if mode == "skip":
            item.add_marker(pytest.mark.skip(reason=f"s390x: {reason}"))
        else:
            item.add_marker(pytest.mark.xfail(reason=f"s390x: {reason}", strict=False))
