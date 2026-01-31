#!/bin/bash
# Cryptnox CLI Universal Installer
# Supports: Native (pip + apt), Snap, Deb
#
# Usage: curl -fsSL https://raw.githubusercontent.com/cryptnox-snap/cryptnox-installer/main/install.sh | bash
#    or: ./install.sh [--native|--snap|--deb]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Version from PyPI
get_latest_version() {
    curl -fsSL https://pypi.org/pypi/cryptnox-cli/json 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4
}

VERSION="${CRYPTNOX_VERSION:-$(get_latest_version)}"
VERSION="${VERSION:-1.0.3}"

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "$(uname -m)" ;;
    esac
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_NAME=$PRETTY_NAME
    else
        OS=$(uname -s)
        OS_VERSION=$(uname -r)
        OS_NAME=$OS
    fi

    # Package manager
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

    HAS_SNAP=$(command -v snap &>/dev/null && echo true || echo false)

    log_info "OS: $OS_NAME"
    log_info "Architecture: $(detect_arch)"
    log_info "Package manager: $PKG_MANAGER"
}

# Install system dependencies via apt/dnf/etc
install_system_deps() {
    log_info "Installing system dependencies..."

    case $PKG_MANAGER in
        apt)
            sudo apt-get update
            sudo apt-get install -y \
                pcscd \
                libpcsclite1 \
                pcsc-tools \
                python3-pip \
                python3-venv \
                python3-pyscard \
                swig \
                libpcsclite-dev
            ;;
        dnf|yum)
            sudo $PKG_MANAGER install -y \
                pcsc-lite \
                pcsc-lite-libs \
                pcsc-tools \
                python3-pip \
                python3-pyscard \
                swig \
                pcsc-lite-devel
            ;;
        pacman)
            sudo pacman -Syu --noconfirm \
                pcsclite \
                ccid \
                python-pip \
                python-pyscard \
                swig
            ;;
        zypper)
            sudo zypper install -y \
                pcsc-lite \
                pcsc-ccid \
                python3-pip \
                python3-pyscard \
                swig \
                pcsc-lite-devel
            ;;
        *)
            log_warn "Unknown package manager. Install pcscd manually."
            ;;
    esac

    # Enable pcscd
    if command -v systemctl &>/dev/null; then
        sudo systemctl enable pcscd 2>/dev/null || true
        sudo systemctl start pcscd 2>/dev/null || true
    fi

    log_success "System dependencies installed"
}

# Install via pip (Native method - RECOMMENDED)
install_native() {
    log_info "Installing via pip (native method)..."

    install_system_deps

    # Install cryptnox-cli via pip
    log_info "Installing cryptnox-cli via pip..."

    # Try with --break-system-packages (Python 3.11+)
    if pip3 install --user --break-system-packages cryptnox-cli 2>/dev/null; then
        log_success "Installed via pip"
    elif pip3 install --user cryptnox-cli 2>/dev/null; then
        log_success "Installed via pip"
    else
        log_error "pip install failed"
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
    log_info "Installing via Snap..."

    if ! command -v snap &>/dev/null; then
        log_info "Installing snapd..."
        case $PKG_MANAGER in
            apt)
                sudo apt-get update && sudo apt-get install -y snapd
                ;;
            dnf|yum)
                sudo $PKG_MANAGER install -y snapd
                sudo systemctl enable --now snapd.socket
                sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
                ;;
            *)
                log_error "Cannot install snapd automatically"
                return 1
                ;;
        esac
    fi

    sudo snap install cryptnox

    log_info "Connecting interfaces..."
    sudo snap connect cryptnox:raw-usb || true
    sudo snap connect cryptnox:hardware-observe || true

    log_success "Installed via Snap"
    log_info "Use: cryptnox.card"
}

# Install via Deb package (experimental - may have dependency issues)
install_deb() {
    log_info "Installing via Deb package..."
    log_warn "Note: Deb package may have Python dependency issues"
    log_warn "Consider using --native instead for best compatibility"

    if [ "$PKG_MANAGER" != "apt" ]; then
        log_error "Deb installation requires apt"
        return 1
    fi

    install_system_deps

    # Detect architecture and OS
    ARCH=$(detect_arch)
    case "$OS" in
        ubuntu)
            case "$OS_VERSION" in
                24.*) OS_VER="ubuntu-24.04" ;;
                *) OS_VER="ubuntu-22.04" ;;
            esac
            ;;
        *) OS_VER="ubuntu-22.04" ;;
    esac

    RELEASE_URL="https://github.com/cryptnox-snap/cryptnox-installer/releases/latest/download"
    DEB_FILE="cryptnox-cli_${VERSION}-1_${ARCH}_${OS_VER}.deb"

    log_info "Downloading: ${DEB_FILE}"
    if curl -fsSL -o "/tmp/${DEB_FILE}" "${RELEASE_URL}/${DEB_FILE}"; then
        sudo dpkg -i "/tmp/${DEB_FILE}" || sudo apt-get install -f -y
        rm -f "/tmp/${DEB_FILE}"

        # Install pip dependencies (deb package doesn't include all Python deps)
        log_info "Installing Python dependencies via pip..."
        pip3 install --user --break-system-packages cryptnox-sdk-py lazy-import tabulate 2>/dev/null || \
        pip3 install --user cryptnox-sdk-py lazy-import tabulate 2>/dev/null || true

        log_success "Installed via Deb"
        log_info "Use: cryptnox"
    else
        log_error "Failed to download deb package"
        log_info "Falling back to native installation..."
        install_native
    fi
}

# Uninstall
uninstall() {
    log_info "Uninstalling cryptnox..."

    # Snap
    if command -v snap &>/dev/null && snap list cryptnox &>/dev/null 2>&1; then
        log_info "Removing snap..."
        sudo snap remove cryptnox
    fi

    # Deb
    if dpkg -l cryptnox-cli 2>/dev/null | grep -q "^ii"; then
        log_info "Removing deb..."
        sudo apt-get remove -y cryptnox-cli
        sudo apt-get autoremove -y
    fi

    # Pip
    if pip3 show cryptnox-cli &>/dev/null 2>&1; then
        log_info "Removing pip package..."
        pip3 uninstall -y cryptnox-cli 2>/dev/null || \
        pip3 uninstall --break-system-packages -y cryptnox-cli 2>/dev/null || true
    fi

    log_success "Uninstall complete"
}

# Update
update() {
    detect_os

    # Snap
    if command -v snap &>/dev/null && snap list cryptnox &>/dev/null 2>&1; then
        log_info "Updating snap..."
        sudo snap refresh cryptnox
        return
    fi

    # Pip
    if pip3 show cryptnox-cli &>/dev/null 2>&1; then
        log_info "Updating pip package..."
        pip3 install --user --upgrade cryptnox-cli 2>/dev/null || \
        pip3 install --user --upgrade --break-system-packages cryptnox-cli 2>/dev/null
        return
    fi

    log_warn "cryptnox not installed"
}

# Show version
show_version() {
    echo ""
    log_info "Installed versions:"

    # Snap
    if command -v snap &>/dev/null && snap list cryptnox &>/dev/null 2>&1; then
        echo "  Snap: $(snap list cryptnox 2>/dev/null | tail -1 | awk '{print $2}')"
    fi

    # Deb
    if dpkg -l cryptnox-cli 2>/dev/null | grep -q "^ii"; then
        echo "  Deb:  $(dpkg -l cryptnox-cli | grep "^ii" | awk '{print $3}')"
    fi

    # Pip
    if pip3 show cryptnox-cli &>/dev/null 2>&1; then
        echo "  Pip:  $(pip3 show cryptnox-cli 2>/dev/null | grep "^Version:" | awk '{print $2}')"
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
    if systemctl is-active pcscd &>/dev/null; then
        echo -e "${GREEN}running${NC}"
    else
        echo -e "${RED}stopped${NC}"
    fi

    # Snap connections
    if command -v snap &>/dev/null && snap list cryptnox &>/dev/null 2>&1; then
        echo ""
        echo "  Snap interfaces:"
        snap connections cryptnox 2>/dev/null | grep -E "raw-usb|hardware" | sed 's/^/    /'
    fi

    show_version
}

# Setup card reader
setup_reader() {
    log_info "Setting up card reader..."

    cat << 'EOF' | sudo tee /etc/modprobe.d/blacklist-nfc.conf > /dev/null
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
