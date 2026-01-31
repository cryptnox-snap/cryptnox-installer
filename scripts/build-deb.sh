#!/bin/bash
# Build Debian package for cryptnox-cli
# Usage: ./build-deb.sh [version]
#
# Supports: Debian 12+, Ubuntu 22.04+, Linux Mint 21+

set -e

# Capture script location BEFORE any cd commands
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"

VERSION="${1:-1.0.3}"
PKG_NAME="cryptnox-cli"
BUILD_DIR="${BUILD_DIR:-$(mktemp -d /tmp/cryptnox-deb-build.XXXXXX)}"
SKIP_DEPS="${SKIP_DEPS:-false}"

echo "=== Building ${PKG_NAME} ${VERSION} deb package ==="
echo "Build directory: ${BUILD_DIR}"
echo "Repo root: ${REPO_ROOT}"

# Cleanup previous build if using default location (skip in CI for artifact upload)
if [[ "${BUILD_DIR}" == /tmp/cryptnox-deb-build.* ]] && [[ "${CI}" != "true" ]]; then
    trap "rm -rf ${BUILD_DIR}" EXIT
fi
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Download source from PyPI (using curl for reliability in CI)
echo "Downloading ${PKG_NAME} ${VERSION} from PyPI..."
PKG_NAME_UNDERSCORE="${PKG_NAME//-/_}"
TAR_FILE="${PKG_NAME_UNDERSCORE}-${VERSION}.tar.gz"
PYPI_URL="https://files.pythonhosted.org/packages/source/${PKG_NAME_UNDERSCORE:0:1}/${PKG_NAME_UNDERSCORE}/${TAR_FILE}"

if ! curl -fsSL -o "${TAR_FILE}" "${PYPI_URL}"; then
    # Fallback: get URL from PyPI JSON API
    echo "Direct download failed, trying PyPI API..."
    PYPI_URL=$(curl -s "https://pypi.org/pypi/${PKG_NAME}/${VERSION}/json" | \
        python3 -c "import sys,json; urls=json.load(sys.stdin)['urls']; print(next(u['url'] for u in urls if u['packagetype']=='sdist'))")
    curl -fsSL -o "${TAR_FILE}" "${PYPI_URL}"
fi
echo "Extracting ${TAR_FILE}..."
tar -xzf "${TAR_FILE}"

# Find extracted directory (usually package_name-version)
SRC_DIR="${PKG_NAME_UNDERSCORE}-${VERSION}"
if [ ! -d "${SRC_DIR}" ]; then
    SRC_DIR=$(find . -maxdepth 1 -type d -name "${PKG_NAME}*" -o -name "${PKG_NAME_UNDERSCORE}*" | grep -v "^\.$" | head -1)
fi
if [ -z "${SRC_DIR}" ] || [ ! -d "${SRC_DIR}" ]; then
    echo "Error: Could not find extracted source directory"
    ls -la
    exit 1
fi

# Rename to Debian standard format
DEBIAN_DIR="${PKG_NAME}-${VERSION}"
mv "${SRC_DIR}" "${DEBIAN_DIR}"
cd "${DEBIAN_DIR}"

# Copy debian directory from repo root
if [ -d "${REPO_ROOT}/debian" ]; then
    cp -r "${REPO_ROOT}/debian" .
    echo "Copied debian/ from ${REPO_ROOT}"
else
    echo "Error: debian/ directory not found at ${REPO_ROOT}"
    exit 1
fi

# Update changelog version if different
if [ "${VERSION}" != "1.0.3" ]; then
    sed -i "s/1.0.3-1/${VERSION}-1/g" debian/changelog
fi

# Install build dependencies (skip with SKIP_DEPS=true)
if [ "${SKIP_DEPS}" != "true" ]; then
    echo "Installing build dependencies..."
    sudo apt-get update
    sudo apt-get install -y \
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
        fakeroot
else
    echo "Skipping dependency installation (SKIP_DEPS=true)"
fi

# Build the package
echo "Building package..."
dpkg-buildpackage -us -uc -b

# Copy results
echo "=== Build complete ==="
echo "Packages are in: ${BUILD_DIR}"
ls -la "${BUILD_DIR}"/*.deb 2>/dev/null || echo "No .deb files found"

# Copy artifacts to workspace for CI
if [[ -n "${GITHUB_WORKSPACE}" ]]; then
    mkdir -p "${GITHUB_WORKSPACE}/dist"
    cp "${BUILD_DIR}"/*.deb "${GITHUB_WORKSPACE}/dist/" 2>/dev/null || true
    echo "Artifacts copied to: ${GITHUB_WORKSPACE}/dist/"
    ls -la "${GITHUB_WORKSPACE}/dist/"
fi

echo ""
echo "To install: sudo dpkg -i ${BUILD_DIR}/${PKG_NAME}_${VERSION}-1_*.deb"
echo "Then fix dependencies: sudo apt-get install -f"
