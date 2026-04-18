#!/usr/bin/env bash
# ==============================================================================
# Fedora Setup Script
# Configures a fresh Fedora installation with essential tools, drivers, and apps.
# ==============================================================================

set -eo pipefail

# Default environment configuration
: "${USE_SUDO:=true}" "${DEBUG:=false}" "${DOTFILES_DIR:=.}"

# Terminal color codes for output formatting
declare -Ar COLORS=(
  [black]=30 [red]=31 [green]=32 [yellow]=33
  [blue]=34 [magenta]=35 [cyan]=36 [white]=37
)

# Spinner frames for long-running tasks
readonly SPINNERS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# ------------------------------------------------------------------------------
# Utility Functions
# ------------------------------------------------------------------------------

has_command() { command -v "$1" &>/dev/null; }

print_success() { printf "\r\033[%sm✓\033[0m %s\033[K\n" "${COLORS[green]}" "$1"; }
print_error() { printf "\r\033[%sm[ERROR] %s\033[0m\033[K\n" "${COLORS[red]}" "$1"; exit 1; }
print_warning() { printf "\n\r\033[%sm[!] %s\033[0m\033[K\n" "${COLORS[yellow]}" "$1"; }
print_section() { printf "\n\033[1;34m==> %s\033[0m\n" "${1}"; }

run_as_root() {
  if [[ "$EUID" -ne 0 ]] && [[ "$USE_SUDO" == "true" ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

# Executes a command with a loading spinner, capturing output on failure
execute() {
  local msg="$1" tmp pid i=0
  shift

  # In debug mode, run command directly and display output
  if [[ "${DEBUG}" == "true" ]]; then
    if "$@"; then
      print_success "$msg"
    else
      print_error "$msg"
    fi
    return
  fi

  # Create a temporary file to store standard and error outputs
  tmp=$(mktemp)
  "$@" >"$tmp" 2>&1 &
  pid=$!

  # Loop the spinner animation while the background process is running
  while kill -0 $pid 2>/dev/null; do
    printf "\r\033[36m%s\033[0m %s...\033[K" "${SPINNERS[i]}" "$msg"
    i=$(( (i + 1) % ${#SPINNERS[@]} ))
    sleep 0.08
  done

  # Process completed, check the exit status
  if wait $pid; then
    print_success "$msg"
  else
    printf "\r\033[%sm✖ %s (failed)\033[0m\033[K\n" "${COLORS[red]}" "$msg"
    cat "$tmp"
    rm -f "$tmp"
    exit 1
  fi
  rm -f "$tmp"
}

execute_root() { execute "$1" run_as_root "${@:2}"; }

# Wrapper for installing packages across multiple managers
install_packages() {
  local mgr="$1" msg="$2"; shift 2
  case "$mgr" in
    dnf) execute_root "$msg" dnf install -y -q "$@" ;;
    flatpak) execute_root "$msg" flatpak install -y flathub "$@" ;;
    *) print_error "Unsupported manager '$mgr'. Supported: 'dnf', 'flatpak'." ;;
  esac
}

add_dnf_repo() {
  local name="$1" type="$2" url="$3"
  case "$type" in
    repofile)
      local dest
      dest="/etc/yum.repos.d/$(basename "$url")"
      execute_root "Add $name repository" curl -sLo "$dest" "$url"
      ;;
    copr) execute_root "Enable $name COPR repository" dnf copr enable -y "$url" ;;
    *) print_error "Unsupported DNF repo type '$type'. Supported: 'repofile', 'copr'." ;;
  esac
}

check_tool() {
  has_command "$1" || print_error "Missing dependency: '$1'. $2"
}

copy_file() {
  local src="$1"
  local dest="$2"
  local desc="${3:-$(basename "$1")}"

  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    print_success "Configured $desc"
  else
    print_warning "$desc not found at $src"
  fi
}

append_if_missing() {
  local file="$1"
  local search_string="$2"
  local line_to_append="$3"

  if ! grep -q "$search_string" "$file" 2>/dev/null; then
    printf "%s\n" "$line_to_append" >> "$file"
  fi
}

download_extract() {
  local url="$1"
  local dest="$2"
  local msg="$3"

  mkdir -p "$dest"
  execute "$msg" bash -c "set -e; tmp=\$(mktemp); trap 'rm -f \"\$tmp\"' EXIT; curl -sSfL '$url' -o \"\$tmp\"; tar -xJ -f \"\$tmp\" -C '$dest'"
}

# ------------------------------------------------------------------------------
# Dependency & Configuration Maps
# ------------------------------------------------------------------------------

declare -A DEPS=(
  [dnf]="Required for packages." [curl]="Required for downloads."
  [tar]="Required for extraction." [xz]="Required for decompression."
  [fc-cache]="Required for updating fonts."
)

declare -A CFGS=(
  ["${DOTFILES_DIR}/config/starship.toml"]="$HOME/.config/starship.toml|Starship prompt"
  ["${DOTFILES_DIR}/config/zed/settings.json"]="$HOME/.config/zed/settings.json|Zed editor settings"
)

# ------------------------------------------------------------------------------
# Core Setup Steps
# ------------------------------------------------------------------------------

init_os() {
  local os
  os=$(uname | tr '[:upper:]' '[:lower:]')

  if [[ "$os" != "linux" ]]; then
    print_error "Script supported on Linux only. Detected OS: $os."
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" != "fedora" ]]; then
      print_warning "This script is highly optimized for Fedora Linux."
    fi
  fi
}

remove_default_bloat() {
  print_section "Cleaning Default Bloatware..."

  local pkgs=(gnome-tour gnome-connections gnome-contacts gnome-weather ptyxis
              gnome-maps gnome-calendar gnome-boxes libreoffice\* firefox)

  execute_root "Remove pre-installed applications" dnf remove -y "${pkgs[@]}"
}

install_system_packages_and_drivers() {
  print_section "Installing System Packages & Hardware Drivers..."

  local dnf_cfg="/etc/dnf/dnf.conf"
  execute_root "Optimize DNF configuration" bash -c "
    grep -q '^fastestmirror=True' $dnf_cfg || printf 'fastestmirror=True\n' >> $dnf_cfg
    grep -q '^max_parallel_downloads=' $dnf_cfg || printf 'max_parallel_downloads=10\n' >> $dnf_cfg
    grep -q '^install_weak_deps=' $dnf_cfg || printf 'install_weak_deps=False\n' >> $dnf_cfg
  "

  # Setup Repositories First
  add_dnf_repo "GitHub CLI" "repofile" "https://cli.github.com/packages/rpm/gh-cli.repo"
  add_dnf_repo "Starship" "copr" "atim/starship"
  add_dnf_repo "Ghostty" "copr" "scottames/ghostty"

  local fv
  fv=$(rpm -E %fedora)
  local rpmfusion_base="https://mirrors.rpmfusion.org"
  install_packages dnf "Install RPMFusion Repositories" \
    "${rpmfusion_base}/free/fedora/rpmfusion-free-release-${fv}.noarch.rpm" \
    "${rpmfusion_base}/nonfree/fedora/rpmfusion-nonfree-release-${fv}.noarch.rpm"

  local nvidia_repo="https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo"
  add_dnf_repo "NVIDIA container toolkit" "repofile" "$nvidia_repo"

  # Extract and import GPG keys for the NVIDIA toolkit securely
  # shellcheck disable=SC2016
  execute_root "Import NVIDIA GPG keys" bash -c '
    repo_file="/etc/yum.repos.d/nvidia-container-toolkit.repo"
    awk -F= "tolower(\$1)==\"gpgkey\"{print \$2}" "$repo_file" | \
      tr " " "\n" | sed "/^$/d" | sort -u | xargs -r -n1 rpm --import
  '

  # Refresh cache and update existing packages now that all repos are added
  execute_root "Update DNF packages & refresh cache" dnf update -y -q

  # Single DNF transaction for all packages and drivers
  install_packages dnf "Install core tools & hardware drivers" \
    dnf5-plugins git just starship micro gh ghostty onedrive \
    akmod-nvidia xorg-x11-drv-nvidia-cuda nvidia-container-toolkit

  local font_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.tar.xz"
  local font_dest="$HOME/.local/share/fonts/FiraCode"

  download_extract "$font_url" "$font_dest" "Install FiraCode Nerd Font"
  execute "Update font cache" fc-cache -r
}

install_apps() {
  print_section "Installing Applications..."

  if ! has_command flatpak; then
    install_packages dnf "Install flatpak daemon" flatpak
  fi

  local flathub_repo="https://dl.flathub.org/repo/flathub.flatpakrepo"
  execute_root "Add Flathub remote repository" flatpak remote-add --if-not-exists flathub "$flathub_repo"

  install_packages flatpak "Install Flatpak applications" \
    org.mozilla.firefox org.gnome.gitlab.somas.Apostrophe com.mattjakeman.ExtensionManager

  execute_root "Update flatpak applications" flatpak update -y
  execute "Install Zed Editor" bash -c "curl -s -f https://zed.dev/install.sh | sh"
}

configure_dotfiles() {
  print_section "Configuring Dotfiles..."

  touch "$HOME/.bashrc"

  # Ensure Starship initializes correctly in bash
  # shellcheck disable=SC2016
  local bash_init='eval "$(starship init bash)"'
  append_if_missing "$HOME/.bashrc" "starship init bash" "$bash_init"

  # Copy over defined configuration files to their expected locations
  for src in "${!CFGS[@]}"; do
    IFS='|' read -r dest desc <<< "${CFGS[$src]}"
    copy_file "$src" "$dest" "${desc:-Config}"
  done
}

post_install() {
  print_section "Finalizing Setup..."

  execute_root "Generate AKMODS keys" /usr/sbin/kmodgenca -a

  # Import the generated MOK key automatically. Password is set to 'password'
  if ! has_command mokutil; then
    print_warning "mokutil is missing. Installing it now..."
    install_packages dnf "Install mokutil" mokutil
  fi

  if mokutil --sb-state &>/dev/null; then
    execute_root "Import MOK key for Secure Boot" bash -c "
      printf 'password\npassword\n' | \
        mokutil --import /etc/pki/akmods/certs/public_key.der
    "
  else
    print_warning "EFI variables not supported. Skipping MOK key import."
  fi

  execute_root "Remove orphaned packages" dnf autoremove -y -q

  print_warning "Reboot required to load NVIDIA drivers. MOKManager password is: 'password'"
}

# ------------------------------------------------------------------------------
# Entrypoint & Argument Parsing
# ------------------------------------------------------------------------------

show_help() {
  printf "Usage: %s [OPTIONS]\n\n" "$0"
  printf "Options:\n"
  printf "  -d, --dotfiles-dir <dir>  Path to dotfiles directory (default: current)\n"
  printf "  --no-sudo                 Run script without invoking sudo (for root/containers)\n"
  printf "  --debug                   Enable verbose debug logging output\n"
  printf "  -h, --help                Show this help message and exit\n"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dotfiles-dir)
        shift
        if [[ $# -ne 0 ]]; then
          export DOTFILES_DIR="$1"
        else
          print_error "Missing argument for directory parameter (-d/--dotfiles-dir)."
        fi
        ;;
      --no-sudo) USE_SUDO="false" ;;
      --debug) export DEBUG="true" ;;
      -h|--help) show_help; exit 0 ;;
      *) print_error "Unrecognized argument: '$1'. Use -h or --help for usage information." ;;
    esac
    shift
  done
}

main() {
  [[ "${DEBUG}" == "true" ]] && set -x
  trap '[[ $? -eq 0 ]] || print_error "Setup aborted unexpectedly. Check logs for details."' EXIT

  if [[ -f "$DOTFILES_DIR/header.txt" ]]; then
    cat "$DOTFILES_DIR/header.txt"
  fi

  init_os

  # Ensure essential build and runtime tools exist before proceeding
  for tool in "${!DEPS[@]}"; do
    check_tool "$tool" "${DEPS[$tool]}"
  done

  # Run the core setup flow
  remove_default_bloat
  install_system_packages_and_drivers
  install_apps
  configure_dotfiles
  post_install
}

# Initialize script
parse_args "$@"
main
