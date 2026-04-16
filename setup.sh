#!/usr/bin/env bash

# Setup script optimized for Fedora.

: "${USE_SUDO:=true}"
: "${DEBUG:=false}"
: "${DOTFILES_DIR:=.}"

# --- Helpers & Logging ---

print_color() { printf "\r\033[%sm%s\033[0m %s\033[K\n" "$1" "$2" "$3"; }
print_spinner() { printf "\r\033[36m%s\033[0m %s\033[K" "$1" "$2"; }
print_success() { print_color "32" "✔" "$1"; }
print_failure() { print_color "31" "✖" "$1 (failed)"; }
print_section() { echo -e "\n\033[1;34m==> ${1}\033[0m"; }
print_warning() { echo -e "\033[1;33m[!] ${1}\033[0m"; }
log_error()     { echo -e "\033[1;31m[ERROR] ${1}\033[0m"; }
print_error()   { log_error "$1"; exit 1; }

runAsRoot() {
  if [ "$EUID" -ne 0 ] && [ "$USE_SUDO" = "true" ]; then
    sudo "${@}"
  else
    "${@}"
  fi
}

execute() {
  local active_msg="$1" done_msg="$2" exit_code tmp_out pid i=0
  local spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  shift 2

  if [ "${DEBUG}" == "true" ]; then
    "$@"
    exit_code=$?
    [ $exit_code -eq 0 ] && print_success "$done_msg" || print_failure "$active_msg"
    return $exit_code
  fi

  tmp_out=$(mktemp)
  "$@" >"$tmp_out" 2>&1 &
  pid=$!

  while kill -0 $pid 2>/dev/null; do
    print_spinner "${spinner[i]}" "$active_msg"
    i=$(( (i + 1) % 10 ))
    sleep 0.08
  done

  wait $pid
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    print_success "$done_msg"
  else
    print_failure "$active_msg"
    cat "$tmp_out"
  fi
  rm -f "$tmp_out"
  return $exit_code
}

execute_root() { execute "$1" "$2" runAsRoot "${@:3}"; }
dnf_install()  { execute_root "Installing $*..." "Installed $*." dnf install -y "$@"; }
flatpak_install() { execute_root "Installing $1 via flatpak..." "Installed $1 via flatpak." flatpak install -y flathub "$1"; }

check_tool() {
  command -v "$1" &> /dev/null || print_error "Could not find $1. $2"
}

# --- Core Phases ---

initOS() {
  [ "$(uname | tr '[:upper:]' '[:lower:]')" != "linux" ] && print_error "This script is only supported on Linux."
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    [ "$ID" != "fedora" ] && print_warning "This script is optimized specifically for Fedora. You are running $ID."
  fi
}

verifySupported() {
  local deps=(
    "dnf:This script requires Fedora's DNF package manager."
    "curl:Please install curl before continuing."
    "sed:It is required for GRUB configuration."
    "tar:Please install tar before continuing."
    "xz:Please install xz before continuing."
    "fc-cache:Please install fontconfig before continuing."
  )
  for dep in "${deps[@]}"; do
    check_tool "${dep%%:*}" "${dep#*:}"
  done
}

removeDefaultBloat() {
  print_section "Cleaning system of default bloat..."
  execute_root "Removing unnecessary default packages..." "Removed unnecessary default packages." \
    dnf remove -y gnome-tour gnome-connections gnome-contacts gnome-weather gnome-maps gnome-calendar gnome-boxes libreoffice\* firefox
}

installSystemPackages() {
  print_section "Installing System Packages..."
  execute_root "Updating DNF packages..." "Updated DNF packages." dnf update -y

  dnf_install dnf5-plugins
  execute_root "Adding GitHub CLI repo..." "Added GitHub CLI repo." dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
  execute_root "Installing GitHub CLI..." "Installed GitHub CLI." dnf install -y gh --repo gh-cli

  execute_root "Enabling Starship COPR..." "Enabled Starship COPR." dnf copr enable -y atim/starship
  dnf_install just starship

  local font_dir="$HOME/.local/share/fonts/FiraCode"
  mkdir -p "$font_dir"
  execute "Downloading and extracting FiraCode..." "Downloaded and extracted FiraCode." sh -c "curl -s -L 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.tar.xz' | tar -xJ -C '$font_dir'"
  execute "Updating font cache..." "Updated font cache." fc-cache -r
}

installHardwareDrivers() {
  print_section "Installing Hardware Drivers..."
  local fv; fv=$(rpm -E %fedora)

  dnf_install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fv}.noarch.rpm" \
              "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fv}.noarch.rpm"
  dnf_install akmod-nvidia xorg-x11-drv-nvidia-cuda

  execute_root "Adding NVIDIA container toolkit repo..." "Added NVIDIA container toolkit repo." \
    sh -c "curl -fsSL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo -o /etc/yum.repos.d/nvidia-container-toolkit.repo"

  export DEBUG
  execute_root "Importing NVIDIA repo GPG keys..." "Imported NVIDIA repo GPG keys." bash -c '
    set -euo pipefail
    repo=/etc/yum.repos.d/nvidia-container-toolkit.repo
    mapfile -t keys < <(awk -F= "tolower(\$1)==\"gpgkey\"{print \$2}" "$repo" | tr " " "\n" | sed "/^$/d" | sort -u)
    [ "${#keys[@]}" -eq 0 ] && { echo "No gpgkey entries found in $repo" >&2; exit 1; }
    for key in "${keys[@]}"; do
      echo "Importing NVIDIA GPG key: $key"
      rpm --import "$key"
    done
    [ "${DEBUG:-false}" == "true" ] && { echo "Imported GPG keys:"; rpm -qa "gpg-pubkey*"; }
    exit 0
  '

  execute_root "Refreshing DNF cache..." "Refreshed DNF caches." dnf makecache -y --disablerepo="*" --enablerepo="nvidia-container-toolkit*"
  dnf_install nvidia-container-toolkit
}

installApps() {
  print_section "Installing GUI Applications..."
  command -v flatpak &> /dev/null || dnf_install flatpak
  execute_root "Adding flathub remote..." "Added flathub remote." flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  for app in org.mozilla.firefox md.obsidian.Obsidian; do
    flatpak_install "$app"
  done
  execute_root "Updating flatpak packages..." "Updated flatpak packages." flatpak update -y
  execute "Installing Zed editor..." "Installed Zed editor." sh -c "curl -s -f https://zed.dev/install.sh | sh"
}

copy_dotfile() {
  local src="$1" dest="$2"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  else
    print_warning "$(basename "$src") not found in $(dirname "$src")"
  fi
}

configureDotfiles() {
  print_section "Configuring user settings and dotfiles..."
  grep -q 'starship init bash' "$HOME/.bashrc" || printf "\neval \"\$(starship init bash)\"\n" >> "$HOME/.bashrc"
  copy_dotfile "${DOTFILES_DIR}/config/starship.toml" "$HOME/.config/starship.toml"
  copy_dotfile "${DOTFILES_DIR}/config/zed/settings.json" "$HOME/.config/zed/settings.json"
}

postInstall() {
  print_section "Finalizing Setup..."
  execute_root "Generating AKMODS key..." "Generated AKMODS key." /usr/sbin/kmodgenca
  execute_root "Importing MOK key..." "Imported MOK key." mokutil --import /etc/pki/akmods/certs/public_key.der
  echo ""
  print_warning "A reboot is required to enroll NVIDIA modules signing key with Secure Boot."
  print_warning "Run \`mokutil --test-key /etc/pki/akmods/certs/public_key.der\` after reboot to confirm the key is enrolled."
  echo ""
}

fail_trap() {
  local res=$?
  [ "$res" != "0" ] && log_error "Setup failed or was aborted."
  exit "$res"
}

help() {
  echo -e "\033[1;34mSetup Script Usage\033[0m\n\nOptions:"
  echo -e "  \033[1;32m-h, --help                \033[0m Show this help message and exit"
  echo -e "  \033[1;32m-d, --dotfiles-dir <dir>  \033[0m Path to dotfiles directory (default: .)"
  echo -e "  \033[1;32m    --no-sudo             \033[0m Run without sudo privileges"
  echo -e "  \033[1;32m    --debug               \033[0m Run with debug output enabled"
}

# --- Execution ---

set -u
while [[ $# -gt 0 ]]; do
  case $1 in
    '--dotfiles-dir'|-d)
       shift
       if [[ $# -ne 0 ]]; then
           export DOTFILES_DIR="${1}"
       else
           print_error "Please provide the dotfiles directory path."
       fi
       ;;
    '--no-sudo') USE_SUDO="false" ;;
    '--debug') export DEBUG="true" ;;
    '--help'|-h) help; exit 0 ;;
    *) log_error "Unknown arguments: $1"; help; exit 1 ;;
  esac
  shift
done
set +u

[ "${DEBUG}" == "true" ] && set -x
trap "fail_trap" EXIT
set -e

initOS
verifySupported
removeDefaultBloat
installSystemPackages
installHardwareDrivers
installApps
configureDotfiles
postInstall
