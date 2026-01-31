#!/bin/bash
# Build Debian package for cryptnox-cli
# Usage: ./build-deb.sh [version]
#
# Supports: Debian 12+, Ubuntu 22.04+, Linux Mint 21+

set -euo pipefail

# Capture script location BEFORE any cd commands
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"

VERSION="${1:-1.0.3}"
PKG_NAME="cryptnox-cli"
BUILD_DIR="${BUILD_DIR:-$(mktemp -d /tmp/cryptnox-deb-build.XXXXXX)}"
SKIP_DEPS="${SKIP_DEPS:-false}"
CI="${CI:-false}"

# Validate version format (semver: X.Y.Z or X.Y.Z-suffix)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: Invalid version format: $VERSION (expected X.Y.Z)"
    exit 1
fi

echo "=== Building ${PKG_NAME} ${VERSION} deb package ==="
echo "Build directory: ${BUILD_DIR}"
echo "Repo root: ${REPO_ROOT}"

# Cleanup function
cleanup() {
    local dir="${BUILD_DIR}"
    if [[ -n "$dir" ]] && [[ -d "$dir" ]]; then
        rm -rf "$dir"
    fi
}

# Cleanup previous build if using default location (skip in CI for artifact upload)
if [[ "${BUILD_DIR}" == /tmp/cryptnox-deb-build.* ]] && [[ "${CI}" != "true" ]]; then
    trap cleanup EXIT
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Download source from PyPI (using curl for reliability in CI)
echo "Downloading ${PKG_NAME} ${VERSION} from PyPI..."
PKG_NAME_UNDERSCORE="${PKG_NAME//-/_}"
TAR_FILE="${PKG_NAME_UNDERSCORE}-${VERSION}.tar.gz"
PYPI_URL="https://files.pythonhosted.org/packages/source/${PKG_NAME_UNDERSCORE:0:1}/${PKG_NAME_UNDERSCORE}/${TAR_FILE}"

if ! curl -fsSL --connect-timeout 30 -o "${TAR_FILE}" "${PYPI_URL}"; then
    # Fallback: get URL from PyPI JSON API
    echo "Direct download failed, trying PyPI API..."
    PYPI_URL=$(curl -fsSL --connect-timeout 30 "https://pypi.org/pypi/${PKG_NAME}/${VERSION}/json" | \
        python3 -c "import sys,json; urls=json.load(sys.stdin)['urls']; print(next(u['url'] for u in urls if u['packagetype']=='sdist'))")
    if ! curl -fsSL --connect-timeout 30 -o "${TAR_FILE}" "${PYPI_URL}"; then
        echo "Error: Failed to download source from PyPI"
        exit 1
    fi
fi

echo "Extracting ${TAR_FILE}..."
tar -xzf "${TAR_FILE}"

# Find extracted directory (usually package_name-version)
SRC_DIR="${PKG_NAME_UNDERSCORE}-${VERSION}"
if [[ ! -d "${SRC_DIR}" ]]; then
    SRC_DIR=$(find . -maxdepth 1 -type d -name "${PKG_NAME}*" -o -name "${PKG_NAME_UNDERSCORE}*" | grep -v '^\.$' | head -1)
fi
if [[ -z "${SRC_DIR}" ]] || [[ ! -d "${SRC_DIR}" ]]; then
    echo "Error: Could not find extracted source directory"
    ls -la
    exit 1
fi

# Rename to Debian standard format
DEBIAN_DIR="${PKG_NAME}-${VERSION}"
mv "${SRC_DIR}" "${DEBIAN_DIR}"
cd "${DEBIAN_DIR}"

# Copy debian directory from repo root
if [[ -d "${REPO_ROOT}/debian" ]]; then
    cp -r "${REPO_ROOT}/debian" .
    echo "Copied debian/ from ${REPO_ROOT}"
else
    echo "Error: debian/ directory not found at ${REPO_ROOT}"
    exit 1
fi

# Update changelog version if different
if [[ "${VERSION}" != "1.0.3" ]]; then
    sed -i "s/1.0.3-1/${VERSION}-1/g" debian/changelog
fi

# Use sudo if available and not root
SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
        SUDO="sudo"
    else
        echo "Warning: Not root and sudo not available, some commands may fail"
    fi
fi

# Install build dependencies (skip with SKIP_DEPS=true)
if [[ "${SKIP_DEPS}" != "true" ]]; then
    echo "Installing build dependencies..."
    if ! $SUDO apt-get update; then
        echo "Error: apt-get update failed"
        exit 1
    fi
    if ! $SUDO apt-get install -y \
        build-essential \
        debhelper \
        dh-python \
        python3-all \
        python3-setuptools \
        python3-pip \
        pybuild-plugin-pyproject \
        swig \
        libpcsclite-dev \
        pcscd \
        devscripts \
        fakeroot; then
        echo "Error: apt-get install failed"
        exit 1
    fi
else
    echo "Skipping dependency installation (SKIP_DEPS=true)"
fi

# Build the package
echo "Building package..."
if ! dpkg-buildpackage -us -uc -b; then
    echo "Error: dpkg-buildpackage failed"
    exit 1
fi

# Copy results
echo "=== Build complete ==="
echo "Packages are in: ${BUILD_DIR}"
ls -la "${BUILD_DIR}"/*.deb 2>&1 || echo "No .deb files found"

# Copy artifacts to workspace for CI
if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    mkdir -p "${GITHUB_WORKSPACE}/dist"
    if cp "${BUILD_DIR}"/*.deb "${GITHUB_WORKSPACE}/dist/" 2>&1; then
        echo "Artifacts copied to: ${GITHUB_WORKSPACE}/dist/"
        ls -la "${GITHUB_WORKSPACE}/dist/"
    else
        echo "Warning: Could not copy artifacts to workspace"
    fi
fi

echo ""
echo "To install: sudo dpkg -i ${BUILD_DIR}/${PKG_NAME}_${VERSION}-1_*.deb"
echo "Then fix dependencies: sudo apt-get install -f"
