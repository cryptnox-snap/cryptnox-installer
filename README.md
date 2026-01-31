<p align="center">
  <img src="https://cryptnox.com/bv-wp-content/uploads/2023/05/cryptnox-logo.png" alt="Cryptnox" width="300">
</p>

<h1 align="center">Cryptnox Installer</h1>

<p align="center">
  <strong>Universal installer for Cryptnox CLI on Linux</strong>
</p>

<p align="center">
  <a href="#quick-install">Quick Install</a> •
  <a href="#supported-distributions">Distributions</a> •
  <a href="#manual-installation">Manual Install</a> •
  <a href="#card-reader-setup">Card Reader</a> •
  <a href="#commands">Commands</a>
</p>

---

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/kokoye2007/cryptnox-installer/main/install.sh | bash
```

Or download and run:

```bash
wget https://raw.githubusercontent.com/kokoye2007/cryptnox-installer/main/install.sh
chmod +x install.sh
./install.sh
```

---

## Supported Distributions

| Distribution | Architecture | Method | Status |
|--------------|--------------|--------|--------|
| Ubuntu 22.04+ | amd64 / arm64 | Snap / Deb | ✅ |
| Debian 12+ | amd64 / arm64 | Snap / Deb | ✅ |
| Linux Mint 21+ | amd64 / arm64 | Snap / Deb | ✅ |
| Fedora 38+ | amd64 / arm64 | Snap / Pip | ✅ |
| Arch Linux | amd64 / arm64 | Snap / Pip | ✅ |
| openSUSE | amd64 / arm64 | Snap / Pip | ✅ |

---

## Installation Options

### Native (Recommended)

```bash
./install.sh --native
```

Installs system dependencies via apt/dnf + cryptnox-cli via pip. This is the most reliable method.

### Other Methods

```bash
./install.sh --native  # pip + apt dependencies (RECOMMENDED)
./install.sh --snap    # Install via Snap Store
./install.sh --deb     # Install via Debian package (experimental)
```

**Note:** The `--deb` option may have Python dependency issues. Use `--native` for best compatibility.

---

## Management Commands

```bash
./install.sh --update      # Update to latest version
./install.sh --uninstall   # Remove Cryptnox
./install.sh --version     # Show installed version
./install.sh --status      # Check system status
```

---

## Card Reader Setup

For USB NFC readers (like ACR122U), you may need to blacklist kernel modules:

```bash
./install.sh --setup
```

Or manually:

```bash
echo "blacklist pn533_usb" | sudo tee /etc/modprobe.d/blacklist-nfc.conf
sudo reboot
```

---

## Manual Installation

### From Snap Store

```bash
sudo snap install cryptnox
sudo snap connect cryptnox:raw-usb
sudo snap connect cryptnox:hardware-observe
```

### From Deb Package

```bash
# For amd64 (x86_64)
wget https://github.com/kokoye2007/cryptnox-installer/releases/latest/download/cryptnox-cli_1.0.3-1_amd64_ubuntu-24.04.deb

# For arm64 (aarch64/Raspberry Pi)
wget https://github.com/kokoye2007/cryptnox-installer/releases/latest/download/cryptnox-cli_1.0.3-1_arm64_ubuntu-24.04.deb

# Install
sudo dpkg -i cryptnox-cli_*.deb
sudo apt-get install -f
```

### From PyPI

```bash
pip install cryptnox-cli
```

---

## Build From Source

### Build Deb Package

```bash
git clone https://github.com/kokoye2007/cryptnox-installer.git
cd cryptnox-installer
./scripts/build-deb.sh
```

---

## Usage

After installation:

```bash
# Snap installation
cryptnox.card --help

# Deb/Pip installation
cryptnox --help
```

### Quick Commands

```bash
cryptnox card info       # Show card information
cryptnox card init       # Initialize a new card
cryptnox btc send        # Send Bitcoin
cryptnox eth send        # Send Ethereum
```

---

## Requirements

- **Hardware**: Cryptnox Smart Card + USB Card Reader
- **OS**: Linux (amd64 or arm64)
- **Python**: 3.11+ (for pip install)

---

## Troubleshooting

### Card Reader Not Detected

1. Check if pcscd is running:
   ```bash
   sudo systemctl status pcscd
   ```

2. Restart the service:
   ```bash
   sudo systemctl restart pcscd
   ```

3. Blacklist NFC modules:
   ```bash
   ./install.sh --setup
   ```

### Snap Permission Issues

```bash
sudo snap connect cryptnox:raw-usb
sudo snap connect cryptnox:hardware-observe
```

---

## Links

- [Cryptnox Website](https://www.cryptnox.com)
- [Cryptnox Shop](https://shop.cryptnox.com)
- [PyPI Package](https://pypi.org/project/cryptnox-cli/)
- [Snap Store](https://snapcraft.io/cryptnox)
- [Documentation](https://docs.cryptnox.com)

---

## License

LGPL-3.0 - See [LICENSE](LICENSE) for details.

---

<p align="center">
  Made with ❤️ for the Cryptnox community
</p>
