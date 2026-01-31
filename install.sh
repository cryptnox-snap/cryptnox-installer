#!/bin/bash
# Cryptnox CLI Universal Installer
# Supports: Native (pip + apt), Snap, Deb
#
# Recommended usage (download first, then run):
#   wget https://raw.githubusercontent.com/cryptnox-snap/cryptnox-installer/main/install.sh
#   chmod +x install.sh && ./install.sh
#
# Or: ./install.sh [--native|--snap|--deb]

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Global variables
SUDO=""
OS=""
OS_VERSION=""
OS_NAME=""
PKG_MANAGER=""
HAS_SNAP="false"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Cleanup on exit
cleanup() {
    rm -f /tmp/cryptnox-cli_*.deb /tmp/SHA256SUMS 2>/dev/null || true
}
trap cleanup EXIT

# Version from PyPI
get_latest_version() {
    local version
    if version=$(curl -fsSL --connect-timeout 10 https://pypi.org/pypi/cryptnox-cli/json 2>&1); then
        echo "$version" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4
    else
        log_warn "Could not fetch version from PyPI, using default"
        echo ""
    fi
}

# Validate version format (semver-like: X.Y.Z)
validate_version() {
    local ver="$1"
    if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        log_error "Invalid version format: $ver (expected X.Y.Z)"
        exit 1
    fi
}

# Verify SHA256 checksum
verify_checksum() {
    local file="$1"
    local expected="$2"

    if [[ -z "$expected" ]]; then
        log_warn "No checksum provided, skipping verification"
        return 0
    fi

    local actual
    actual=$(sha256sum "$file" | cut -d' ' -f1)

    if [[ "$actual" != "$expected" ]]; then
        log_error "Checksum mismatch!"
        log_error "  Expected: $expected"
        log_error "  Got:      $actual"
        rm -f "$file"
        return 1
    fi

    log_success "Checksum verified"
    return 0
}

# Check if sudo is available
check_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        SUDO=""
        return 0
    fi

    if ! command -v sudo &>/dev/null; then
        log_error "sudo is required but not installed"
        log_error "Please run as root or install sudo"
        exit 1
    fi
    SUDO="sudo"
}

# Get version
VERSION="${CRYPTNOX_VERSION:-$(get_latest_version)}"
VERSION="${VERSION:-1.0.3}"

# Validate version
validate_version "$VERSION"

# Detect architecture
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "$arch" ;;
    esac
}

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_NAME="${PRETTY_NAME:-$OS}"
    else
        OS="$(uname -s)"
        OS_VERSION="$(uname -r)"
        OS_NAME="$OS"
    fi

    # Package manager detection
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
    else
        PKG_MANAGER="unknown"
    fi

    if command -v snap &>/dev/null; then
        HAS_SNAP="true"
    else
        HAS_SNAP="false"
    fi

    log_info "OS: $OS_NAME"
    log_info "Architecture: $(detect_arch)"
    log_info "Package manager: $PKG_MANAGER"
}

# Install system dependencies via apt/dnf/etc
install_system_deps() {
    check_sudo
    log_info "Installing system dependencies..."

    case "$PKG_MANAGER" in
        apt)
            $SUDO apt-get update || { log_error "apt-get update failed"; return 1; }
            $SUDO apt-get install -y \
                pcscd \
                libpcsclite1 \
                pcsc-tools \
                python3-pip \
                python3-venv \
                python3-pyscard \
                swig \
                libpcsclite-dev || { log_error "apt-get install failed"; return 1; }
            ;;
        dnf|yum)
            $SUDO "$PKG_MANAGER" install -y \
                pcsc-lite \
                pcsc-lite-libs \
                pcsc-tools \
                python3-pip \
                python3-pyscard \
                swig \
                pcsc-lite-devel || { log_error "$PKG_MANAGER install failed"; return 1; }
            ;;
        pacman)
            $SUDO pacman -Syu --noconfirm \
                pcsclite \
                ccid \
                python-pip \
                python-pyscard \
                swig || { log_error "pacman install failed"; return 1; }
            ;;
        zypper)
            $SUDO zypper install -y \
                pcsc-lite \
                pcsc-ccid \
                python3-pip \
                python3-pyscard \
                swig \
                pcsc-lite-devel || { log_error "zypper install failed"; return 1; }
            ;;
        *)
            log_warn "Unknown package manager ($PKG_MANAGER). Install pcscd manually."
            return 0
            ;;
    esac

    # Enable pcscd
    if command -v systemctl &>/dev/null; then
        if ! $SUDO systemctl enable pcscd; then
            log_warn "Could not enable pcscd service"
        fi
        if ! $SUDO systemctl start pcscd; then
            log_warn "Could not start pcscd service"
        fi
    fi

    log_success "System dependencies installed"
}

# Install via pip (Native method - RECOMMENDED)
install_native() {
    log_info "Installing via pip (native method)..."

    install_system_deps || return 1

    log_info "Installing cryptnox-cli via pip..."

    # Try with --break-system-packages first (Python 3.11+), then without
    local pip_result=0
    if pip3 install --user --break-system-packages cryptnox-cli 2>&1; then
        log_success "Installed via pip"
    elif pip3 install --user cryptnox-cli 2>&1; then
        log_success "Installed via pip"
    else
        log_error "pip install failed"
        pip_result=1
    fi

    if [[ $pip_result -ne 0 ]]; then
        return 1
    fi

    # Check PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_warn "Add ~/.local/bin to your PATH:"
        log_warn "  echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.bashrc"
        log_warn "  source ~/.bashrc"
    fi

    log_info "Use: ~/.local/bin/cryptnox or cryptnox (if PATH configured)"
}

# Install via Snap
install_snap() {
    check_sudo
    log_info "Installing via Snap..."

    if ! command -v snap &>/dev/null; then
        log_info "Installing snapd..."
        case "$PKG_MANAGER" in
            apt)
                $SUDO apt-get update || { log_error "apt-get update failed"; return 1; }
                $SUDO apt-get install -y snapd || { log_error "snapd install failed"; return 1; }
                ;;
            dnf|yum)
                $SUDO "$PKG_MANAGER" install -y snapd || { log_error "snapd install failed"; return 1; }
                $SUDO systemctl enable --now snapd.socket || log_warn "Could not enable snapd.socket"
                $SUDO ln -sf /var/lib/snapd/snap /snap || true
                ;;
            *)
                log_error "Cannot install snapd automatically on $PKG_MANAGER"
                return 1
                ;;
        esac
    fi

    $SUDO snap install cryptnox || { log_error "snap install failed"; return 1; }

    log_info "Connecting interfaces..."
    if ! $SUDO snap connect cryptnox:raw-usb; then
        log_warn "Could not connect raw-usb interface"
    fi
    if ! $SUDO snap connect cryptnox:hardware-observe; then
        log_warn "Could not connect hardware-observe interface"
    fi

    log_success "Installed via Snap"
    log_info "Use: cryptnox.card"
}

# Install via Deb package (experimental)
install_deb() {
    check_sudo
    log_info "Installing via Deb package..."
    log_warn "Note: Deb package requires network access during install"
    log_warn "Consider using --native instead for best compatibility"

    if [[ "$PKG_MANAGER" != "apt" ]]; then
        log_error "Deb installation requires apt"
        return 1
    fi

    install_system_deps || return 1

    # Detect architecture and OS
    local arch os_ver
    arch="$(detect_arch)"
    case "$OS" in
        ubuntu)
            case "$OS_VERSION" in
                24.*) os_ver="ubuntu-24.04" ;;
                *) os_ver="ubuntu-22.04" ;;
            esac
            ;;
        *) os_ver="ubuntu-22.04" ;;
    esac

    local release_url="https://github.com/cryptnox-snap/cryptnox-installer/releases/download/v${VERSION}"
    local deb_file="cryptnox-cli_${VERSION}-1_${arch}_${os_ver}.deb"
    local checksum_file="SHA256SUMS"

    log_info "Downloading: ${deb_file}"
    if ! curl -fsSL --connect-timeout 30 -o "/tmp/${deb_file}" "${release_url}/${deb_file}"; then
        log_error "Failed to download deb package"
        log_info "Falling back to native installation..."
        install_native
        return
    fi

    # Verify checksum if available
    if curl -fsSL --connect-timeout 10 -o "/tmp/${checksum_file}" "${release_url}/${checksum_file}" 2>&1; then
        local expected_sum
        expected_sum=$(grep "${deb_file}" "/tmp/${checksum_file}" | cut -d' ' -f1)
        if ! verify_checksum "/tmp/${deb_file}" "$expected_sum"; then
            log_error "Checksum verification failed!"
            rm -f "/tmp/${deb_file}" "/tmp/${checksum_file}"
            exit 1
        fi
        rm -f "/tmp/${checksum_file}"
    else
        log_warn "Checksum file not available, skipping verification"
    fi

    if ! $SUDO dpkg -i "/tmp/${deb_file}"; then
        log_info "Fixing dependencies..."
        $SUDO apt-get install -f -y || { log_error "Could not fix dependencies"; return 1; }
    fi
    rm -f "/tmp/${deb_file}"

    # Install pip dependencies (deb package doesn't include all Python deps)
    log_info "Installing Python dependencies via pip..."
    if ! pip3 install --user --break-system-packages cryptnox-sdk-py lazy-import tabulate 2>&1; then
        if ! pip3 install --user cryptnox-sdk-py lazy-import tabulate 2>&1; then
            log_warn "Some pip dependencies may not have installed correctly"
        fi
    fi

    log_success "Installed via Deb"
    log_info "Use: cryptnox"
}

# Uninstall
uninstall() {
    check_sudo
    log_info "Uninstalling cryptnox..."
    local found=false

    # Snap
    if command -v snap &>/dev/null; then
        if snap list cryptnox &>/dev/null; then
            log_info "Removing snap..."
            if $SUDO snap remove cryptnox; then
                found=true
            else
                log_warn "Failed to remove snap package"
            fi
        fi
    fi

    # Deb
    if dpkg -l cryptnox-cli 2>&1 | grep -q "^ii"; then
        log_info "Removing deb..."
        if $SUDO apt-get remove -y cryptnox-cli; then
            $SUDO apt-get autoremove -y || true
            found=true
        else
            log_warn "Failed to remove deb package"
        fi
    fi

    # Pip
    if pip3 show cryptnox-cli &>/dev/null; then
        log_info "Removing pip package..."
        if pip3 uninstall -y cryptnox-cli 2>&1 || pip3 uninstall --break-system-packages -y cryptnox-cli 2>&1; then
            found=true
        else
            log_warn "Failed to remove pip package"
        fi
    fi

    if [[ "$found" == "true" ]]; then
        log_success "Uninstall complete"
    else
        log_warn "cryptnox was not found"
    fi
}

# Update
update() {
    detect_os
    check_sudo

    # Snap
    if command -v snap &>/dev/null; then
        if snap list cryptnox &>/dev/null; then
            log_info "Updating snap..."
            if $SUDO snap refresh cryptnox; then
                log_success "Snap updated"
            else
                log_error "Snap update failed"
            fi
            return
        fi
    fi

    # Pip
    if pip3 show cryptnox-cli &>/dev/null; then
        log_info "Updating pip package..."
        if pip3 install --user --upgrade cryptnox-cli 2>&1; then
            log_success "Pip package updated"
        elif pip3 install --user --upgrade --break-system-packages cryptnox-cli 2>&1; then
            log_success "Pip package updated"
        else
            log_error "Update failed"
        fi
        return
    fi

    log_warn "cryptnox not installed"
}

# Show version
show_version() {
    echo ""
    log_info "Installed versions:"

    # Snap
    if command -v snap &>/dev/null; then
        if snap list cryptnox &>/dev/null; then
            local snap_ver
            snap_ver=$(snap list cryptnox 2>&1 | tail -1 | awk '{print $2}')
            echo "  Snap: $snap_ver"
        fi
    fi

    # Deb
    if dpkg -l cryptnox-cli 2>&1 | grep -q "^ii"; then
        local deb_ver
        deb_ver=$(dpkg -l cryptnox-cli | grep "^ii" | awk '{print $3}')
        echo "  Deb:  $deb_ver"
    fi

    # Pip
    if pip3 show cryptnox-cli &>/dev/null; then
        local pip_ver
        pip_ver=$(pip3 show cryptnox-cli 2>&1 | grep "^Version:" | awk '{print $2}')
        echo "  Pip:  $pip_ver"
    fi

    echo ""
    echo "  Latest (PyPI): ${VERSION}"
}

# Status
status() {
    detect_os
    echo ""
    log_info "System Status"
    echo ""

    # pcscd
    echo -n "  pcscd: "
    if command -v systemctl &>/dev/null && systemctl is-active pcscd &>/dev/null; then
        echo -e "${GREEN}running${NC}"
    else
        echo -e "${RED}stopped${NC}"
    fi

    # Snap connections
    if command -v snap &>/dev/null; then
        if snap list cryptnox &>/dev/null; then
            echo ""
            echo "  Snap interfaces:"
            snap connections cryptnox 2>&1 | grep -E "raw-usb|hardware" | sed 's/^/    /' || true
        fi
    fi

    show_version
}

# Setup card reader
setup_reader() {
    check_sudo
    log_info "Setting up card reader..."

    cat << 'EOF' | $SUDO tee /etc/modprobe.d/blacklist-nfc.conf > /dev/null
# Blacklist NFC modules for PC/SC compatibility
blacklist nfc
blacklist pn533
blacklist pn533_usb
EOF

    log_success "NFC modules blacklisted"
    log_warn "Reboot required"
}

# Usage
usage() {
    cat << EOF
Cryptnox CLI Installer v${VERSION}

Usage: $0 [COMMAND]

Installation methods:
    --native        Install via pip + apt dependencies (RECOMMENDED)
    --snap          Install via Snap Store
    --deb           Install via Debian package (experimental)

Management:
    --update        Update to latest version
    --uninstall     Remove cryptnox
    --version       Show installed versions
    --status        Show system status
    --setup         Setup card reader (blacklist NFC modules)

    --help          Show this help

Examples:
    $0              # Auto-detect (defaults to native)
    $0 --native     # pip install with apt dependencies
    $0 --snap       # Install from Snap Store
    $0 --update     # Update existing installation

EOF
}

# Main
main() {
    echo ""
    echo "========================================"
    echo "  Cryptnox CLI Installer v${VERSION}"
    echo "========================================"
    echo ""

    case "${1:-}" in
        --native|--pip)
            detect_os
            install_native
            ;;
        --snap)
            detect_os
            install_snap
            ;;
        --deb)
            detect_os
            install_deb
            ;;
        --update)
            update
            ;;
        --uninstall|--remove)
            uninstall
            ;;
        --version|--check)
            show_version
            ;;
        --status)
            status
            ;;
        --setup)
            setup_reader
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        "")
            # Default: native installation
            detect_os
            log_info "Using native installation (pip + apt)"
            log_info "Use --snap for Snap or --deb for Debian package"
            echo ""
            install_native
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac

    echo ""
    log_success "Done!"
    echo ""
}

main "$@"
