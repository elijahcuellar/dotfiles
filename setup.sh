#!/usr/bin/env bash

# Inspired by Helm/Glide installers.

: ${USE_SUDO:="true"}
: ${DEBUG:="false"}
: ${DOTFILES_DIR:="."}

HAS_DNF="$(type "dnf" &> /dev/null && echo true || echo false)"
HAS_FLATPAK="$(type "flatpak" &> /dev/null && echo true || echo false)"
HAS_CURL="$(type "curl" &> /dev/null && echo true || echo false)"
HAS_SED="$(type "sed" &> /dev/null && echo true || echo false)"

# Verify OS compatibility.
initOS() {
  OS=$(echo `uname`|tr '[:upper:]' '[:lower:]')

  if [ "${OS}" != "linux" ]; then
    echo "This script is only supported on Linux."
    exit 1
  fi

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "fedora" ]]; then
      echo "[WARNING] This script is optimized specifically for Fedora. You are running $ID."
    fi
  fi
}

# Run command as root.
runAsRoot() {
  if [ $EUID -ne 0 -a "$USE_SUDO" = "true" ]; then
    sudo "${@}"
  else
    "${@}"
  fi
}

# Execute command with spinner.
execute() {
  local active_msg="$1"
  local done_msg="$2"
  shift 2

  "$@" >/dev/null 2>&1 &
  local pid=$!
  local delay=0.08
  local spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  local i=0

  while kill -0 $pid 2>/dev/null; do
    printf "\r\033[36m%s\033[0m %s\033[K" "${spinner[i]}" "$active_msg"
    i=$(( (i + 1) % 10 ))
    sleep $delay
  done

  wait $pid
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    printf "\r\033[32m✔\033[0m %s\033[K\n" "$done_msg"
  else
    printf "\r\033[31m✖\033[0m %s (failed)\033[K\n" "$active_msg"
  fi
  return $exit_code
}

# Print section header.
print_section() {
  echo -e "\n\033[1;34m==> ${1}\033[0m"
}

# Print warning message.
print_warning() {
  echo -e "\033[1;33m[!] ${1}\033[0m"
}

# Verify dependencies.
verifySupported() {
  if [ "${HAS_DNF}" != "true" ]; then
    echo "[ERROR] Could not find dnf. This script requires Fedora's DNF package manager."
    exit 1
  fi

  if [ "${HAS_CURL}" != "true" ]; then
    echo "[ERROR] Could not find curl. Please install curl before continuing."
    exit 1
  fi

  if [ "${HAS_SED}" != "true" ]; then
    echo "[ERROR] Could not find sed. It is required for GRUB configuration."
    exit 1
  fi
}

# Remove default bloatware.
removeDefaultBloat() {
  print_section "Cleaning system of default bloat..."
  execute "Removing unnecessary default packages..." "Removed unnecessary default packages." runAsRoot dnf remove -y \
    gnome-tour gnome-connections gnome-contacts gnome-weather \
    gnome-maps gnome-calendar gnome-boxes libreoffice\* firefox
}

# Install system packages.
installSystemPackages() {
  print_section "Installing System Packages..."
  execute "Updating DNF packages..." "Updated DNF packages." runAsRoot dnf update -y

  # Install official GitHub CLI via DNF5 explicitly
  execute "Installing DNF5 plugins..." "Installed DNF5 plugins." runAsRoot dnf install -y dnf5-plugins
  execute "Adding GitHub CLI repo..." "Added GitHub CLI repo." runAsRoot dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
  execute "Installing GitHub CLI..." "Installed GitHub CLI." runAsRoot dnf install -y gh --repo gh-cli

  # Install other CLI tools and fonts
  execute "Enabling Starship COPR..." "Enabled Starship COPR." runAsRoot dnf copr enable -y atim/starship
  execute "Installing just, starship..." "Installed just, starship." runAsRoot dnf install -y just starship

  local FONT_DIR="$HOME/.local/share/fonts/FiraCode"
  mkdir -p "$FONT_DIR"
  execute "Downloading and extracting FiraCode..." "Downloaded and extracted FiraCode." sh -c "curl -s -L 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.tar.xz' | tar -xJ -C '$FONT_DIR'"
  execute "Updating font cache..." "Updated font cache." fc-cache -r
}

# Install NVIDIA drivers & toolkit.
installHardwareDrivers() {
  print_section "Installing Hardware Drivers..."

  local fedora_version
  fedora_version=$(rpm -E %fedora)

  execute "Adding RPM Fusion repositories..." "Added RPM Fusion repositories." runAsRoot dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"

  execute "Installing NVIDIA drivers (akmod, cuda)..." "Installed NVIDIA drivers (akmod, cuda)." runAsRoot dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda

  execute "Adding NVIDIA container toolkit repo..." "Added NVIDIA container toolkit repo." runAsRoot sh -c "curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo -o /etc/yum.repos.d/nvidia-container-toolkit.repo"

  execute "Installing NVIDIA container toolkit..." "Installed NVIDIA container toolkit." runAsRoot dnf install -y nvidia-container-toolkit
}

# Install GUI apps.
installApps() {
  print_section "Installing GUI Applications..."

  if [ "${HAS_FLATPAK}" != "true" ]; then
    execute "Installing flatpak..." "Installed flatpak." runAsRoot dnf install -y flatpak
  fi

  # Ensure the flathub remote is configured
  execute "Adding flathub remote..." "Added flathub remote." runAsRoot flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  execute "Installing Firefox via flatpak..." "Installed Firefox via flatpak." runAsRoot flatpak install -y flathub org.mozilla.firefox
  execute "Installing Obsidian via flatpak..." "Installed Obsidian via flatpak." runAsRoot flatpak install -y flathub md.obsidian.Obsidian
  execute "Updating flatpak packages..." "Updated flatpak packages." runAsRoot flatpak update -y

  execute "Installing Zed editor..." "Installed Zed editor." sh -c "curl -s -f https://zed.dev/install.sh | sh"
}

# Configure dotfiles.
configureDotfiles() {
  print_section "Configuring user settings and dotfiles..."

  if ! grep -q 'starship init bash' "$HOME/.bashrc"; then
    printf "\neval \"\$(starship init bash)\"\n" >> "$HOME/.bashrc"
  fi

  if [[ -f "${DOTFILES_DIR}/config/starship.toml" ]]; then
    mkdir -p "$HOME/.config"
    cp "${DOTFILES_DIR}/config/starship.toml" "$HOME/.config/starship.toml"
  else
    echo "[WARNING] starship.toml not found in ${DOTFILES_DIR}/config"
  fi

  if [[ -f "${DOTFILES_DIR}/config/zed/settings.json" ]]; then
    mkdir -p "$HOME/.config/zed"
    cp "${DOTFILES_DIR}/config/zed/settings.json" "$HOME/.config/zed/settings.json"
  else
    echo "[WARNING] settings.json not found in ${DOTFILES_DIR}/config/zed"
  fi
}

# Cleanup on exit.
cleanup() {
  # Add temporary directory cleanup here if any are created in the future
  :
}

# Handle errors.
fail_trap() {
  result=$?
  if [ "$result" != "0" ]; then
    if [[ -n "${INPUT_ARGUMENTS:-}" ]]; then
      echo "Failed to run setup with the arguments provided: $INPUT_ARGUMENTS"
      help
    else
      echo "Failed to run system setup."
    fi
  fi
  cleanup
  exit $result
}

# Show help.
help () {
  echo -e "\033[1;34mSetup Script Usage\033[0m"
  echo
  echo "Options:"
  echo -e "  \033[1;32m-h, --help\033[0m                 Show this help message and exit"
  echo -e "  \033[1;32m-d, --dotfiles-dir <dir>\033[0m   Path to dotfiles directory (default: .)"
  echo -e "  \033[1;32m    --no-sudo\033[0m              Run without sudo privileges"
  echo -e "  \033[1;32m    --debug\033[0m                Run with debug output enabled"
}

# Finalize setup.
finalize() {
  cleanup

  print_section "Finalizing Setup..."
  execute "Generating AKMODS key..." "Generated AKMODS key." runAsRoot /usr/sbin/kmodgenca
  execute "Importing MOK key..." "Imported MOK key." runAsRoot mokutil --import /etc/pki/akmods/certs/public_key.der

  echo ""
  print_warning "A reboot is required to enroll NVIDIA modules signing key with Secure Boot."
  print_warning "Run \`mokutil --test-key /etc/pki/akmods/certs/public_key.der\` after reboot to confirm the key is enrolled."
  echo ""
}

# Execution

# Stop on error.
trap "fail_trap" EXIT
set -e

# Set debug.
if [ "${DEBUG}" == "true" ]; then
  set -x
fi

# Parse arguments.
export INPUT_ARGUMENTS="${@}"
set -u
while [[ $# -gt 0 ]]; do
  case $1 in
    '--dotfiles-dir'|-d)
       shift
       if [[ $# -ne 0 ]]; then
           export DOTFILES_DIR="${1}"
       else
           echo -e "Please provide the dotfiles directory path."
           exit 1
       fi
       ;;
    '--no-sudo')
       USE_SUDO="false"
       ;;
    '--debug')
       export DEBUG="true"
       set -x
       ;;
    '--help'|-h)
       help
       exit 0
       ;;
    *) exit 1
       ;;
  esac
  shift
done
set +u

initOS
verifySupported
removeDefaultBloat
installSystemPackages
installHardwareDrivers
installApps
configureDotfiles
finalize
