#!/usr/bin/env bash
#
# Cloud Agent install script for sonic-mgmt.
#
# Sets up the Python tooling that can actually run inside a Cloud Agent VM
# (no physical/virtual testbed is available here):
#   - Main venv (.venv): repo-wide pre-commit hooks (flake8, yaml/ast checks,
#     ...) plus the tests/common2 quality + unit-test tooling (pylint, mypy,
#     black, isort, pytest, pytest-cov, coverage, pyenchant, ...).
#   - test_reporting/.venv: the test_reporting JUnit XML parser tooling and its
#     unit tests. It gets a dedicated venv (as documented in
#     test_reporting/README.md) because it pins pytest==6.2.5, which conflicts
#     with the newer pytest the common2 tooling wants.
#
# It is intentionally idempotent: it can be re-run against existing venvs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${SONIC_MGMT_VENV:-$REPO_ROOT/.venv}"
REPORTING_VENV_DIR="$REPO_ROOT/test_reporting/.venv"

cd "$REPO_ROOT"

echo "=== sonic-mgmt Cloud Agent install ==="
echo "Repo root:         $REPO_ROOT"
echo "Main virtualenv:   $VENV_DIR"
echo "Reporting venv:    $REPORTING_VENV_DIR"

# --- System packages ---------------------------------------------------------
# pyenchant (used by the common2 pylint spell-check hook) needs the enchant
# runtime + development headers and an aspell dictionary. `make` drives the
# common2 unit-test / coverage targets. Only install when something is missing
# so repeated runs stay fast.
SYS_PKGS=(libenchant-2-2 libenchant-2-dev aspell aspell-en make)
missing_pkgs=()
for pkg in "${SYS_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        missing_pkgs+=("$pkg")
    fi
done
if [ "${#missing_pkgs[@]}" -gt 0 ]; then
    echo "--- Installing system packages: ${missing_pkgs[*]}"
    if command -v sudo >/dev/null 2>&1; then APT="sudo apt-get"; else APT="apt-get"; fi
    $APT -o DPkg::Lock::Timeout=180 update
    DEBIAN_FRONTEND=noninteractive $APT -o DPkg::Lock::Timeout=180 install -y --no-install-recommends "${missing_pkgs[@]}"
else
    echo "--- System packages already present"
fi

# --- Main venv: pre-commit + tests/common2 -----------------------------------
if [ ! -x "$VENV_DIR/bin/python" ]; then
    echo "--- Creating main virtual environment"
    python3 -m venv "$VENV_DIR"
else
    echo "--- Reusing existing main virtual environment"
fi

echo "--- Upgrading pip (main)"
"$VENV_DIR/bin/python" -m pip install --upgrade pip wheel >/dev/null

echo "--- Installing pre-commit"
"$VENV_DIR/bin/pip" install pre-commit

echo "--- Installing tests/common2 requirements"
"$VENV_DIR/bin/pip" install -r tests/common2/requirements.txt

echo "--- Pre-fetching pre-commit hook environments"
# Best effort: hook environments are cached so later `pre-commit run` is fast.
# Do not fail the whole install if the hook repos cannot be fetched (e.g. egress).
"$VENV_DIR/bin/pre-commit" install-hooks || \
    echo "WARN: could not pre-install pre-commit hook environments (network?); they will be fetched on first run."

# --- test_reporting venv -----------------------------------------------------
if [ ! -x "$REPORTING_VENV_DIR/bin/python" ]; then
    echo "--- Creating test_reporting virtual environment"
    python3 -m venv "$REPORTING_VENV_DIR"
else
    echo "--- Reusing existing test_reporting virtual environment"
fi

echo "--- Upgrading pip (test_reporting)"
"$REPORTING_VENV_DIR/bin/python" -m pip install --upgrade pip wheel >/dev/null

echo "--- Installing test_reporting requirements"
"$REPORTING_VENV_DIR/bin/pip" install \
    -r test_reporting/requirements.txt \
    -r test_reporting/requirements_dev.txt

echo "=== Install complete ==="
echo "Main tooling:     source $VENV_DIR/bin/activate"
echo "test_reporting:   source $REPORTING_VENV_DIR/bin/activate"
