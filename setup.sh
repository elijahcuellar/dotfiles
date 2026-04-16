#!/usr/bin/env bash

# Inspired by get-helm-4 installer.

: ${USE_SUDO:="true"}
: ${DEBUG:="false"}
: ${DOTFILES_DIR:="."}

# Verify OS compatibility.
initOS() {
  OS=$(echo `uname`|tr '[:upper:]' '[:lower:]')

  if [ "${OS}" != "linux" ]; then
    print_error "This script is only supported on Linux."
  fi

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "fedora" ]]; then
      print_warning "This script is optimized specifically for Fedora. You are running $ID."
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

  if [ "${DEBUG}" == "true" ]; then
    "$@"
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
      print_success "$done_msg"
    else
      print_failure "$active_msg"
    fi
    return $exit_code
  fi

  local tmp_out
  tmp_out=$(mktemp)

  "$@" >"$tmp_out" 2>&1 &
  local pid=$!
  local delay=0.08
  local spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  local i=0

  while kill -0 $pid 2>/dev/null; do
    print_spinner "${spinner[i]}" "$active_msg"
    i=$(( (i + 1) % 10 ))
    sleep $delay
  done

  wait $pid
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    print_success "$done_msg"
  else
    print_failure "$active_msg"
    cat "$tmp_out"
  fi
  rm -f "$tmp_out"
  return $exit_code
}

# Print spinner frame.
print_spinner() {
  printf "\r\033[36m%s\033[0m %s\033[K" "$1" "$2"
}

# Print success message.
print_success() {
  printf "\r\033[32m✔\033[0m %s\033[K\n" "$1"
}

# Print failure message.
print_failure() {
  printf "\r\033[31m✖\033[0m %s (failed)\033[K\n" "$1"
}

# Print section header.
print_section() {
  echo -e "\n\033[1;34m==> ${1}\033[0m"
}

# Print warning message.
print_warning() {
  echo -e "\033[1;33m[!] ${1}\033[0m"
}

# Print error message.
log_error() {
  echo -e "\033[1;31m[ERROR] ${1}\033[0m"
}

# Print error message and exit.
print_error() {
  log_error "$1"
  exit 1
}

# Check if a tool exists.
check_tool() {
  if ! command -v "$1" &> /dev/null; then
    print_error "Could not find $1. $2"
  fi
}

# Verify dependencies.
verifySupported() {
  check_tool "dnf" "This script requires Fedora's DNF package manager."
  check_tool "curl" "Please install curl before continuing."
  check_tool "sed" "It is required for GRUB configuration."
  check_tool "tar" "Please install tar before continuing."
  check_tool "xz" "Please install xz before continuing."
  check_tool "fc-cache" "Please install fontconfig before continuing."
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

  # Install official GitHub CLI
  execute "Installing DNF5 plugins..." "Installed DNF5 plugins." runAsRoot dnf install -y dnf5-plugins
  execute "Adding GitHub CLI repo..." "Added GitHub CLI repo." runAsRoot dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
  execute "Installing GitHub CLI..." "Installed GitHub CLI." runAsRoot dnf install -y gh --repo gh-cli

  # Install CLI utilities
  execute "Enabling Starship COPR..." "Enabled Starship COPR." runAsRoot dnf copr enable -y atim/starship
  execute "Installing CLI tools and utilities..." "Installed CLI tools and utilities." runAsRoot dnf install -y just starship

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

  # --- NVIDIA container toolkit repo + secure key import ---
  execute "Adding NVIDIA container toolkit repo..." "Added NVIDIA container toolkit repo." \
    runAsRoot sh -c "curl -fsSL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
      -o /etc/yum.repos.d/nvidia-container-toolkit.repo"

  # Import any gpgkey URLs declared by the repo file BEFORE dnf uses the repo (repo_gpgcheck requires this)
  execute "Importing NVIDIA repo GPG keys..." "Imported NVIDIA repo GPG keys." \
    runAsRoot sh -c '
      set -euo pipefail
      repo=/etc/yum.repos.d/nvidia-container-toolkit.repo
      # Extract gpgkey= lines, split on whitespace (repo may list multiple keys), import each
      keys=$(awk -F= '\''tolower($1)=="gpgkey"{print $2}'\'' "$repo" | tr " " "\n" | sed "/^$/d")
      if [ -z "$keys" ]; then
        echo "No gpgkey entries found in $repo" >&2
        exit 1
      fi
      while IFS= read -r key; do
        curl -fsSL "$key" | rpm --import -
      done <<< "$keys"
    '

  # Force metadata refresh now that keys are installed (this is where repomd.xml is verified)
  execute "Refreshing DNF cache (NVIDIA repo)..." "Refreshed DNF cache (NVIDIA repo)." \
    runAsRoot dnf makecache -y --disablerepo="*" --enablerepo="nvidia-container-toolkit*"

  execute "Installing NVIDIA container toolkit..." "Installed NVIDIA container toolkit." \
    runAsRoot dnf install -y nvidia-container-toolkit
}

# Install GUI apps.
installApps() {
  print_section "Installing GUI Applications..."

  if ! command -v flatpak &> /dev/null; then
    execute "Installing flatpak..." "Installed flatpak." runAsRoot dnf install -y flatpak
  fi

  # Ensure the flathub remote is configured
  execute "Adding flathub remote..." "Added flathub remote." runAsRoot flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  for app in org.mozilla.firefox md.obsidian.Obsidian; do
    execute "Installing ${app} via flatpak..." "Installed ${app} via flatpak." runAsRoot flatpak install -y flathub "${app}"
  done
  execute "Updating flatpak packages..." "Updated flatpak packages." runAsRoot flatpak update -y

  execute "Installing Zed editor..." "Installed Zed editor." sh -c "curl -s -f https://zed.dev/install.sh | sh"
}

# Copy configuration file.
copy_dotfile() {
  local src="$1"
  local dest="$2"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  else
    print_warning "$(basename "$src") not found in $(dirname "$src")"
  fi
}

# Configure dotfiles.
configureDotfiles() {
  print_section "Configuring user settings and dotfiles..."

  if ! grep -q 'starship init bash' "$HOME/.bashrc"; then
    printf "\neval \"\$(starship init bash)\"\n" >> "$HOME/.bashrc"
  fi

  copy_dotfile "${DOTFILES_DIR}/config/starship.toml" "$HOME/.config/starship.toml"
  copy_dotfile "${DOTFILES_DIR}/config/zed/settings.json" "$HOME/.config/zed/settings.json"
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
    log_error "Setup failed or was aborted."
  fi
  cleanup
  exit $result
}

# Print help option.
print_help_opt() {
  echo -e "  \033[1;32m${1}\033[0m ${2}"
}

# Show help.
help () {
  echo -e "\033[1;34mSetup Script Usage\033[0m\n"
  echo "Options:"
  print_help_opt "-h, --help                " "Show this help message and exit"
  print_help_opt "-d, --dotfiles-dir <dir>  " "Path to dotfiles directory (default: .)"
  print_help_opt "    --no-sudo             " "Run without sudo privileges"
  print_help_opt "    --debug               " "Run with debug output enabled"
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

# Set debug.
if [ "${DEBUG}" == "true" ]; then
  set -x
fi

# Parse arguments.
set -u
while [[ $# -gt 0 ]]; do
  case $1 in
    '--dotfiles-dir'|-d)
       shift
       if [[ $# -ne 0 ]]; then
           export DOTFILES_DIR="${1}"
       else
           log_error "Please provide the dotfiles directory path."
           help
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
    *) log_error "Unknown arguments: $1"
       help
       exit 1
       ;;
  esac
  shift
done
set +u

# Stop on error.
trap "fail_trap" EXIT
set -e

initOS
verifySupported
removeDefaultBloat
installSystemPackages
installHardwareDrivers
installApps
configureDotfiles
finalize
