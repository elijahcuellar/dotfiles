#!/usr/bin/env bash

# The install script is based off of the MIT-licensed script from glide,
# the package manager for Go: https://github.com/Masterminds/glide.sh/blob/master/get
# and heavily inspired by the Helm installation script architecture.

: ${USE_SUDO:="true"}
: ${DEBUG:="false"}
: ${DOTFILES_DIR:="."}

HAS_DNF="$(type "dnf" &> /dev/null && echo true || echo false)"
HAS_FLATPAK="$(type "flatpak" &> /dev/null && echo true || echo false)"
HAS_CURL="$(type "curl" &> /dev/null && echo true || echo false)"
HAS_SED="$(type "sed" &> /dev/null && echo true || echo false)"

# initOS discovers the operating system for this system.
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

# runs the given command as root (detects if we are root already)
runAsRoot() {
  if [ $EUID -ne 0 -a "$USE_SUDO" = "true" ]; then
    sudo "${@}"
  else
    "${@}"
  fi
}

# verifySupported checks that the necessary tools are present.
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

# installFedoraPackages installs all core system dependencies via DNF.
installFedoraPackages() {
  echo "Installing system packages via DNF..."
  runAsRoot dnf update -y

  # Install official GitHub CLI via DNF5 explicitly
  runAsRoot dnf install -y dnf5-plugins
  runAsRoot dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
  runAsRoot dnf install -y gh --repo gh-cli

  # Install other CLI tools and fonts
  runAsRoot dnf copr enable -y atim/starship
  runAsRoot dnf install -y just starship
  # TODO: install FiraCode Nerd Font
  # https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.tar.xz

  echo "System packages installed."
}

# configureNvidiaWayland installs the NVIDIA drivers, configures Wayland,
# and sets up the Podman CDI via nvidia-container-toolkit.
configureNvidiaWayland() {
  echo "Installing NVIDIA Drivers and Container Toolkit..."

  local fedora_version
  fedora_version=$(rpm -E %fedora)

  runAsRoot dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"

  runAsRoot dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda

  runAsRoot curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo -o /etc/yum.repos.d/nvidia-container-toolkit.repo

  runAsRoot dnf install -y nvidia-container-toolkit

  echo "NVIDIA Drivers and Container Toolkit installed."
}

# installFlatpaks uses Flathub to install requested GUI applications.
installFlatpaks() {
  echo "Installing Obsidian and Zed via Flatpak..."

  if [ "${HAS_FLATPAK}" != "true" ]; then
    echo "Flatpak not found. Installing flatpak via DNF..."
    runAsRoot dnf install -y flatpak
  fi

  # Ensure the flathub remote is configured
  runAsRoot flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  runAsRoot flatpak install -y flathub md.obsidian.Obsidian
  runAsRoot flatpak install -y flathub dev.zed.Zed

  echo "Flatpak applications installed."
}

# configureStarshipAndZed links/copies dotfile configurations into the home directory.
configureStarshipAndZed() {
  echo "Configuring Starship and Zed settings..."

  mkdir -p "$HOME/.config/zed"

  if [[ -f "${DOTFILES_DIR}/starship.toml" ]]; then
    cp "${DOTFILES_DIR}/starship.toml" "$HOME/.config/starship.toml"
  else
    echo "[WARNING] starship.toml not found in ${DOTFILES_DIR}"
  fi

  if [[ -f "${DOTFILES_DIR}/settings.json" ]]; then
    cp "${DOTFILES_DIR}/settings.json" "$HOME/.config/zed/settings.json"
  else
    echo "[WARNING] settings.json not found in ${DOTFILES_DIR}"
  fi

  echo "Starship and Zed configured."
}

# fail_trap is executed if an error occurs.
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

# help provides possible cli installation arguments
help () {
  echo "Accepted cli arguments are:"
  echo -e "\t[--help|-h ] ->> prints this help"
  echo -e "\t[--dotfiles-dir|-d <dir>] ->> path to dotfiles directory (default: .)"
  echo -e "\t[--no-sudo]  ->> run without sudo"
  echo -e "\t[--debug]    ->> run with debug output"
}

# perform any final actions
finalize() {
  # Add temporary directory cleanup here if any are created in the future

  runAsRoot /usr/sbin/kmodgenca
  runAsRoot mokutil --import /etc/pki/akmods/certs/public_key.der

  echo "A reboot is required to enroll NVIDIA modules signing key for Secure Boot."
  echo "After reboot, run `mokutil --test-key /etc/pki/akmods/certs/public_key.der` to check if the key is enrolled."
}

# Execution

# Stop execution on any error
trap "fail_trap" EXIT
set -e

# Set debug if desired
if [ "${DEBUG}" == "true" ]; then
  set -x
fi

# Parsing input arguments (if any)
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
installFedoraPackages
installNVIDIA
installApps
configureStarshipAndZed
finalize
