#!/bin/bash
# Cryptnox CLI Universal Installer
# Supports: Snap, Deb (Debian/Ubuntu/Mint), RPM (Fedora/RHEL), pip (fallback)
#
# Usage: curl -fsSL https://raw.githubusercontent.com/kokoye2007/cryptnox-installer/main/install.sh | bash
#    or: ./install.sh [--snap|--deb|--rpm|--pip]

set -e

# Cleanup on failure
cleanup() {
    rm -f /tmp/cryptnox-cli_*.deb 2>/dev/null || true
}
trap cleanup EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version - fetch from PyPI if not specified
get_latest_version() {
    curl -fsSL https://pypi.org/pypi/cryptnox-cli/json 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4
}

VERSION="${CRYPTNOX_VERSION:-$(get_latest_version)}"
VERSION="${VERSION:-1.0.3}" # Fallback if fetch fails

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if sudo is available
check_sudo() {
    if ! command -v sudo &> /dev/null; then
        log_error "sudo is required but not found. Please install sudo or run as root."
        exit 1
    fi
}

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_NAME=$PRETTY_NAME
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        OS_VERSION=$DISTRIB_RELEASE
        OS_NAME=$DISTRIB_DESCRIPTION
    else
        OS=$(uname -s)
        OS_VERSION=$(uname -r)
        OS_NAME=$OS
    fi

    # Detect package manager
    if command -v snap &> /dev/null; then
        HAS_SNAP=true
    else
        HAS_SNAP=false
    fi

    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
    else
        PKG_MANAGER="unknown"
    fi

    log_info "Detected: $OS_NAME"
    log_info "Package manager: $PKG_MANAGER"
    log_info "Snap available: $HAS_SNAP"
}

# Install system dependencies
install_dependencies() {
    check_sudo
    log_info "Installing system dependencies..."

    case $PKG_MANAGER in
        apt)
            sudo apt-get update
            sudo apt-get install -y pcscd libpcsclite1 pcsc-tools python3-pip python3-pyscard
            ;;
        dnf|yum)
            sudo $PKG_MANAGER install -y pcsc-lite pcsc-lite-libs pcsc-tools python3-pip python3-pyscard
            sudo systemctl enable --now pcscd
            ;;
        pacman)
            sudo pacman -Syu --noconfirm pcsclite ccid python-pip python-pyscard
            sudo systemctl enable --now pcscd
            ;;
        zypper)
            sudo zypper install -y pcsc-lite pcsc-ccid python3-pip python3-pyscard
            sudo systemctl enable --now pcscd
            ;;
        *)
            log_warn "Unknown package manager. Please install pcscd manually."
            ;;
    esac
}

# Install via Snap
install_snap() {
    log_info "Installing via Snap..."

    if ! command -v snap &> /dev/null; then
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
            pacman)
                log_warn "Install snapd from AUR: yay -S snapd"
                return 1
                ;;
            *)
                log_error "Cannot install snapd automatically"
                return 1
                ;;
        esac
    fi

    sudo snap install cryptnox

    log_info "Connecting required interfaces for USB card readers..."
    sudo snap connect cryptnox:raw-usb || true
    sudo snap connect cryptnox:hardware-observe || true

    log_success "Installed via Snap"
    log_info "Use: cryptnox.card"
}

# Detect architecture
detect_arch() {
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$ARCH" in
        amd64|x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) ARCH="$ARCH" ;;
    esac
    echo "$ARCH"
}

# Detect Ubuntu/Debian version for deb package
detect_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu)
                case "$VERSION_ID" in
                    24.*) echo "ubuntu-24.04" ;;
                    22.*) echo "ubuntu-22.04" ;;
                    *) echo "ubuntu-22.04" ;;  # fallback
                esac
                ;;
            debian)
                case "$VERSION_ID" in
                    12*) echo "ubuntu-22.04" ;;  # Debian 12 ~ Ubuntu 22.04
                    *) echo "ubuntu-22.04" ;;
                esac
                ;;
            linuxmint)
                case "$VERSION_ID" in
                    22*) echo "ubuntu-24.04" ;;  # Mint 22 ~ Ubuntu 24.04
                    21*) echo "ubuntu-22.04" ;;  # Mint 21 ~ Ubuntu 22.04
                    *) echo "ubuntu-22.04" ;;
                esac
                ;;
            *)
                echo "ubuntu-22.04"  # default fallback
                ;;
        esac
    else
        echo "ubuntu-22.04"
    fi
}

# Install via Deb package
install_deb() {
    log_info "Installing via Deb package..."

    if [ "$PKG_MANAGER" != "apt" ]; then
        log_error "Deb installation requires apt (Debian/Ubuntu/Mint)"
        return 1
    fi

    install_dependencies

    # Detect architecture and OS version
    ARCH=$(detect_arch)
    OS_VER=$(detect_ubuntu_version)

    log_info "Architecture: $ARCH"
    log_info "OS compatibility: $OS_VER"

    # Check for pre-built deb in releases
    RELEASE_URL="https://github.com/kokoye2007/cryptnox-installer/releases/download/v${VERSION}"
    DEB_FILE="cryptnox-cli_${VERSION}-1_${ARCH}_${OS_VER}.deb"

    log_info "Downloading: ${DEB_FILE}"
    if curl -fsSL -o "/tmp/${DEB_FILE}" "${RELEASE_URL}/${DEB_FILE}" 2>/dev/null; then
        log_info "Installing pre-built package..."
        sudo dpkg -i "/tmp/${DEB_FILE}" || sudo apt-get install -f -y
        rm -f "/tmp/${DEB_FILE}"
    else
        log_warn "Pre-built package not found for ${ARCH}/${OS_VER}"
        log_warn "Falling back to pip installation..."
        install_pip
        return
    fi

    log_success "Installed via Deb"
    log_info "Use: cryptnox"
}

# Install via RPM package
install_rpm() {
    log_info "Installing via RPM/pip for Fedora/RHEL..."

    if [ "$PKG_MANAGER" != "dnf" ] && [ "$PKG_MANAGER" != "yum" ]; then
        log_error "RPM installation requires dnf/yum (Fedora/RHEL/CentOS)"
        return 1
    fi

    install_dependencies

    # RPM not yet available, use pip
    log_info "Installing cryptnox-cli via pip..."
    pip3 install --user cryptnox-cli

    log_success "Installed via pip"
    log_info "Use: ~/.local/bin/cryptnox or add ~/.local/bin to PATH"
}

# Install via pip (fallback)
install_pip() {
    log_info "Installing via pip..."

    install_dependencies

    # Ensure pip is available
    if ! command -v pip3 &> /dev/null; then
        log_error "pip3 not found. Please install python3-pip."
        return 1
    fi

    pip3 install --user cryptnox-cli

    # Add to PATH if needed
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_warn "Add ~/.local/bin to your PATH:"
        log_warn "  echo 'export PATH=\$HOME/.local/bin:\$PATH' >> ~/.bashrc"
    fi

    log_success "Installed via pip"
    log_info "Use: ~/.local/bin/cryptnox"
}

# Setup card reader (blacklist kernel modules)
setup_reader() {
    check_sudo
    log_info "Setting up card reader..."

    cat << 'EOF' | sudo tee /etc/modprobe.d/blacklist-nfc.conf > /dev/null
# Blacklist NFC modules for PC/SC compatibility
blacklist nfc
blacklist pn533
blacklist pn533_usb
EOF

    log_success "NFC modules blacklisted"
    log_warn "Reboot required for changes to take effect"
}

# Check installed version
check_version() {
    log_info "Checking installed versions..."
    echo ""

    # Check snap
    if command -v snap &>/dev/null && snap list cryptnox &>/dev/null 2>&1; then
        echo -e "Snap:    $(snap list cryptnox 2>/dev/null | tail -1 | awk '{print $2}')"
    fi

    # Check deb
    if dpkg -l cryptnox-cli 2>/dev/null | grep -q "^ii"; then
        echo -e "Deb:     $(dpkg -l cryptnox-cli | grep "^ii" | awk '{print $3}')"
    fi

    # Check rpm
    if rpm -q cryptnox-cli &>/dev/null 2>&1; then
        echo -e "RPM:     $(rpm -q --qf '%{VERSION}' cryptnox-cli)"
    fi

    # Check pip
    if pip3 show cryptnox-cli &>/dev/null 2>&1; then
        echo -e "Pip:     $(pip3 show cryptnox-cli 2>/dev/null | grep "^Version:" | awk '{print $2}')"
    fi

    # Check PyPI latest
    LATEST=$(get_latest_version)
    echo ""
    echo -e "Latest (PyPI): ${LATEST:-unknown}"
}

# Uninstall cryptnox
uninstall() {
    log_info "Uninstalling cryptnox..."

    local found=false

    # Remove snap
    if command -v snap &>/dev/null && snap list cryptnox &>/dev/null 2>&1; then
        log_info "Removing snap package..."
        sudo snap remove cryptnox
        found=true
    fi

    # Remove deb
    if dpkg -l cryptnox-cli 2>/dev/null | grep -q "^ii"; then
        log_info "Removing deb package..."
        sudo apt-get remove -y cryptnox-cli
        sudo apt-get autoremove -y
        found=true
    fi

    # Remove rpm
    if rpm -q cryptnox-cli &>/dev/null 2>&1; then
        log_info "Removing rpm package..."
        if command -v dnf &>/dev/null; then
            sudo dnf remove -y cryptnox-cli
        else
            sudo yum remove -y cryptnox-cli
        fi
        found=true
    fi

    # Remove pip
    if pip3 show cryptnox-cli &>/dev/null 2>&1; then
        log_info "Removing pip package..."
        pip3 uninstall -y cryptnox-cli
        found=true
    fi

    if [ "$found" = true ]; then
        log_success "Uninstall complete"
    else
        log_warn "cryptnox not found"
    fi
}

# Update cryptnox
update() {
    detect_os
    log_info "Updating cryptnox..."

    # Update snap
    if command -v snap &>/dev/null && snap list cryptnox &>/dev/null 2>&1; then
        log_info "Updating snap..."
        sudo snap refresh cryptnox
        log_success "Snap updated"
        return
    fi

    # Update deb - reinstall
    if dpkg -l cryptnox-cli 2>/dev/null | grep -q "^ii"; then
        log_info "Updating deb package..."
        install_deb
        return
    fi

    # Update rpm - reinstall
    if rpm -q cryptnox-cli &>/dev/null 2>&1; then
        log_info "Updating rpm package..."
        install_rpm
        return
    fi

    # Update pip
    if pip3 show cryptnox-cli &>/dev/null 2>&1; then
        log_info "Updating pip package..."
        pip3 install --user --upgrade cryptnox-cli
        log_success "Pip package updated"
        return
    fi

    log_warn "cryptnox not installed. Installing now..."
    auto_install
}

# Status check
status() {
    detect_os
    echo ""
    log_info "System Status"
    echo ""

    # Show architecture
    ARCH=$(detect_arch)
    echo "Architecture:  $ARCH"

    # Check pcscd service
    echo -n "pcscd service: "
    if systemctl is-active pcscd &>/dev/null; then
        echo -e "${GREEN}running${NC}"
    else
        echo -e "${RED}stopped${NC}"
    fi

    # Check card readers
    echo -n "Card readers:  "
    if command -v pcsc_scan &>/dev/null; then
        READERS=$(timeout 2 pcsc_scan -r 2>/dev/null | grep -c "Reader" || echo "0")
        echo "${READERS} detected"
    elif command -v cryptnox.pcsc-scan &>/dev/null; then
        READERS=$(timeout 2 cryptnox.pcsc-scan -r 2>/dev/null | grep -c "Reader" || echo "0")
        echo "${READERS} detected"
    else
        echo "pcsc_scan not available"
    fi

    # Check snap connections
    if command -v snap &>/dev/null && snap list cryptnox &>/dev/null 2>&1; then
        echo ""
        log_info "Snap Connections:"
        snap connections cryptnox 2>/dev/null | grep -E "raw-usb|hardware-observe" || echo "  (none)"
    fi

    echo ""
    check_version
}

# Auto-detect best installation method
auto_install() {
    detect_os

    echo ""
    log_info "Selecting best installation method..."

    # Priority: Snap > Deb > RPM/pip > pip
    case $OS in
        ubuntu|debian|linuxmint|pop|elementary|zorin)
            if [ "$HAS_SNAP" = true ]; then
                install_snap
            else
                install_deb
            fi
            ;;
        fedora|rhel|centos|rocky|alma)
            if [ "$HAS_SNAP" = true ]; then
                install_snap
            else
                install_rpm
            fi
            ;;
        arch|manjaro|endeavouros)
            if [ "$HAS_SNAP" = true ]; then
                install_snap
            else
                install_pip
            fi
            ;;
        opensuse*)
            if [ "$HAS_SNAP" = true ]; then
                install_snap
            else
                install_pip
            fi
            ;;
        *)
            log_warn "Unknown distribution: $OS"
            log_info "Trying pip installation..."
            install_pip
            ;;
    esac
}

# Show usage
usage() {
    cat << EOF
Cryptnox CLI Universal Installer

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    (none)      Auto-detect and install
    --snap      Install via Snap
    --deb       Install via Deb package
    --rpm       Install via RPM/pip
    --pip       Install via pip

    --update    Update to latest version
    --uninstall Remove cryptnox
    --version   Show installed versions
    --status    Show system status

    --setup     Setup card reader (blacklist NFC modules)
    --help      Show this help

Environment variables:
    CRYPTNOX_VERSION    Version to install (default: latest)

Examples:
    $0                  # Auto-detect and install
    $0 --snap           # Install via Snap
    $0 --update         # Update to latest
    $0 --uninstall      # Remove cryptnox
    $0 --status         # Check system status

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
        --snap)
            detect_os
            install_snap
            echo ""
            log_success "Installation complete!"
            ;;
        --deb)
            detect_os
            install_deb
            echo ""
            log_success "Installation complete!"
            ;;
        --rpm)
            detect_os
            install_rpm
            echo ""
            log_success "Installation complete!"
            ;;
        --pip)
            detect_os
            install_pip
            echo ""
            log_success "Installation complete!"
            ;;
        --update)
            update
            ;;
        --uninstall|--remove)
            uninstall
            ;;
        --version|--check)
            check_version
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
            auto_install
            echo ""
            log_success "Installation complete!"
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac

    echo ""
}

main "$@"
