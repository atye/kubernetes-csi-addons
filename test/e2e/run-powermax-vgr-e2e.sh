#!/bin/bash
# PowerMax VolumeGroupReplication E2E Test Runner
#
# Clones the kubernetes-csi-addons repo and executes the external
# VolumeGroupReplication e2e tests against a PowerMax-backed cluster
# using a hardcoded config file (powermax-vgr-e2e-config.yaml).
#
# Prerequisites:
#   - A running Kubernetes cluster with CSI-PowerMax + csi-addons deployed
#   - kubectl configured (or KUBECONFIG set)
#   - Go 1.22+ installed
#   - git installed
#   - The powermax-vgr-e2e-config.yaml file updated with your array IDs
#
# Usage:
#   ./run-powermax-vgr-e2e.sh [--branch <branch>] [--timeout <duration>]
#
# Examples:
#   ./run-powermax-vgr-e2e.sh
#   ./run-powermax-vgr-e2e.sh --branch release-0.13
#   ./run-powermax-vgr-e2e.sh --timeout 90m

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/powermax-vgr-e2e-config.yaml"
REPO_URL="https://github.com/csi-addons/kubernetes-csi-addons.git"
# TEMPORARY: Use local repo at /root/kubernetes-csi-addons instead of cloning
CLONE_DIR="/root/kubernetes-csi-addons"
BRANCH="main"
TIMEOUT="60m"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --config|-c)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--branch <branch>] [--timeout <duration>] [--config|-c <path>]"
            echo ""
            echo "Options:"
            echo "  --branch         Branch/tag of kubernetes-csi-addons to clone (default: main)"
            echo "  --timeout        Go test timeout (default: 60m)"
            echo "  --config, -c     Path to e2e config YAML (default: powermax-vgr-e2e-config.yaml)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
echo "============================================="
echo " PowerMax VolumeGroupReplication E2E Runner"
echo "============================================="

if ! command -v go &>/dev/null; then
    echo "ERROR: go is not installed or not in PATH"
    exit 1
fi

if ! command -v git &>/dev/null; then
    echo "ERROR: git is not installed or not in PATH"
    exit 1
fi

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}"
    echo "Copy powermax-vgr-e2e-config.yaml and update array IDs before running."
    exit 1
fi

# Quick sanity: warn if placeholder array IDs are still present
if grep -q '<REMOTE_ARRAY_ID>' "${CONFIG_FILE}"; then
    echo "WARNING: Config file still contains placeholder <REMOTE_ARRAY_ID>."
    echo "         Update ${CONFIG_FILE} with real array IDs before running."
    echo ""
fi

echo "Config file : ${CONFIG_FILE}"
echo "Repo branch : ${BRANCH}"
echo "Test timeout: ${TIMEOUT}"
echo "KUBECONFIG  : ${KUBECONFIG:-<default>}"
echo ""

# ---------------------------------------------------------------------------
# Use local kubernetes-csi-addons repo (TEMPORARY - skip clone/update)
# ---------------------------------------------------------------------------
if [ ! -d "${CLONE_DIR}" ]; then
    echo "ERROR: Local repo not found at ${CLONE_DIR}"
    echo "Please ensure /root/kubernetes-csi-addons exists and is updated."
    exit 1
fi
echo ">>> Using local kubernetes-csi-addons at ${CLONE_DIR} ..."

echo ""

# ---------------------------------------------------------------------------
# Resolve the absolute path to the config so it works from any cwd
# ---------------------------------------------------------------------------
ABS_CONFIG="$(cd "$(dirname "${CONFIG_FILE}")" && pwd)/$(basename "${CONFIG_FILE}")"

# ---------------------------------------------------------------------------
# Run VolumeGroupReplication e2e tests
# ---------------------------------------------------------------------------
echo ">>> Running VolumeGroupReplication e2e tests ..."
echo ""

cd "${CLONE_DIR}"

go test -v \
    -count=1 \
    -timeout "${TIMEOUT}" \
    ./test/e2e/volumegroupreplication/... \
    -e2e-config "${ABS_CONFIG}" \
    -ginkgo.v \

TEST_EXIT=$?

echo ""
if [ ${TEST_EXIT} -eq 0 ]; then
    echo "============================================="
    echo " VolumeGroupReplication e2e tests PASSED"
    echo "============================================="
else
    echo "============================================="
    echo " VolumeGroupReplication e2e tests FAILED"
    echo "============================================="
fi

exit ${TEST_EXIT}
