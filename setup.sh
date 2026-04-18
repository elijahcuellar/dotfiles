#!/usr/bin/env bash
set -eo pipefail

: "${USE_SUDO:=true}" "${DEBUG:=false}" "${DOTFILES_DIR:=.}"

declare -Ar COLORS=(
  [black]=30 [red]=31 [green]=32 [yellow]=33
  [blue]=34 [magenta]=35 [cyan]=36 [white]=37
)
readonly SPINNERS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

print_success() {
  printf "\r\033[%sm✓\033[0m %s\033[K\n" "${COLORS[green]}" "$1"
}
print_error() {
  printf "\r\033[%sm[ERROR] %s\033[0m\033[K\n" "${COLORS[red]}" "$1"
  exit 1
}
print_warning() { printf "\n\r\033[%sm[!] %s\033[0m\033[K\n" "${COLORS[yellow]}" "$1"; }
print_section() { printf "\n\033[1;34m==> %s\033[0m\n" "${1}"; }

run_as_root() {
  [[ "$EUID" -ne 0 ]] && [[ "$USE_SUDO" == "true" ]] && sudo "$@" || "$@"
}

execute() {
  local msg="$1" tmp pid i=0; shift
  if [[ "${DEBUG}" == "true" ]]; then
    "$@" && print_success "$msg" || print_error "$msg"
    return
  fi

  tmp=$(mktemp)
  "$@" >"$tmp" 2>&1 & pid=$!

  while kill -0 $pid 2>/dev/null; do
    printf "\r\033[36m%s\033[0m %s...\033[K" "${SPINNERS[i]}" "$msg"
    i=$(( (i + 1) % ${#SPINNERS[@]} )); sleep 0.08
  done

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

install_packages() {
  local mgr="$1" msg="$2"; shift 2
  case "$mgr" in
    dnf) execute_root "$msg" dnf install -y -q "$@" ;;
    flatpak) execute_root "$msg" flatpak install -y flathub "$@" ;;
    *) print_error "Unsupported package manager '$mgr'." ;;
  esac
}

add_dnf_repo() {
  local name="$1" type="$2" url="$3"
  case "$type" in
    repofile)
      local dest="/etc/yum.repos.d/$(basename "$url")"
      execute_root "Add $name" curl -sLo "$dest" "$url"
      ;;
    copr) execute_root "Enable $name COPR" dnf copr enable -y "$url" ;;
    *) print_error "Unsupported DNF repo type '$type'." ;;
  esac
}

check_tool() {
  command -v "$1" &>/dev/null || print_error "Missing dep: '$1'. $2"
}

copy_file() {
  local src="$1" dest="$2" desc="${3:-$(basename "$1")}"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"
    print_success "Configured $desc"
  else
    print_warning "$desc not found at $src"
  fi
}

append_if_missing() { grep -q "$2" "$1" 2>/dev/null || printf "%s\n" "$3" >> "$1"; }

download_extract() {
  local url="$1" dest="$2" msg="$3"
  mkdir -p "$dest"
  execute "$msg" bash -c "curl -s -L '$url' | tar -xJ -C '$dest'"
}

declare -A DEPS=(
  [dnf]="Required for packages." [curl]="Required for downloads."
  [tar]="Required for extraction." [xz]="Required for decompression."
  [fc-cache]="Required for fonts."
)

declare -A CFGS=(
  ["${DOTFILES_DIR}/config/starship.toml"]="$HOME/.config/starship.toml|Starship"
  ["${DOTFILES_DIR}/config/zed/settings.json"]="$HOME/.config/zed/settings.json|Zed"
)

init_os() {
  local os; os=$(uname | tr '[:upper:]' '[:lower:]')
  [[ "$os" != "linux" ]] && print_error "Supported on Linux only. Detected $os."
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    [[ "${ID:-}" != "fedora" ]] && print_warning "Optimized for Fedora." || true
  fi
}

remove_default_bloat() {
  print_section "Cleaning bloat..."
  local pkgs=(gnome-tour gnome-connections gnome-contacts gnome-weather
              gnome-maps gnome-calendar gnome-boxes libreoffice\* firefox)
  execute_root "Remove bloat" dnf remove -y "${pkgs[@]}"
}

install_system_packages() {
  print_section "Installing System Packages..."

  local dnf_cfg="/etc/dnf/dnf.conf"
  execute_root "Optimize DNF config" bash -c "
    grep -q '^fastestmirror=True' $dnf_cfg || printf 'fastestmirror=True\n' >> $dnf_cfg
    grep -q '^max_parallel_downloads=' $dnf_cfg || printf 'max_parallel_downloads=10\n' >> $dnf_cfg
  "

  execute_root "Update DNF packages" dnf update -y -q
  add_dnf_repo "GitHub CLI" "repofile" "https://cli.github.com/packages/rpm/gh-cli.repo"
  add_dnf_repo "Starship" "copr" "atim/starship"

  install_packages dnf "Install core tools" dnf5-plugins git just starship
  install_packages dnf "Install GitHub CLI" gh --repo gh-cli

  local url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.tar.xz"
  download_extract "$url" "$HOME/.local/share/fonts/FiraCode" "Install FiraCode"
  execute "Update font cache" fc-cache -r
}

install_hardware_drivers() {
  print_section "Installing Hardware Drivers..."
  local fv; fv=$(rpm -E %fedora)
  local base="https://mirrors.rpmfusion.org"
  install_packages dnf "Install RPMFusion" \
    "${base}/free/fedora/rpmfusion-free-release-${fv}.noarch.rpm" \
    "${base}/nonfree/fedora/rpmfusion-nonfree-release-${fv}.noarch.rpm"

  install_packages dnf "Install NVIDIA drivers" akmod-nvidia xorg-x11-drv-nvidia-cuda

  local repo="https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo"
  add_dnf_repo "NVIDIA toolkit" "repofile" "$repo"

  execute_root "Import GPG keys" bash -c '
    repo=/etc/yum.repos.d/nvidia-container-toolkit.repo
    awk -F= "tolower(\$1)==\"gpgkey\"{print \$2}" "$repo" | \
      tr " " "\n" | sed "/^$/d" | sort -u | xargs -r -n1 rpm --import
  '

  execute_root "Refresh DNF" dnf makecache -y -q --disablerepo="*" \
    --enablerepo="nvidia-container-toolkit*"
  install_packages dnf "Install NVIDIA toolkit" nvidia-container-toolkit
}

install_apps() {
  print_section "Installing Apps..."
  if ! command -v flatpak &>/dev/null; then
    install_packages dnf "Install flatpak" flatpak
  fi
  local fh="https://dl.flathub.org/repo/flathub.flatpakrepo"
  execute_root "Add flathub" flatpak remote-add --if-not-exists flathub "$fh"
  install_packages flatpak "Install apps" org.mozilla.firefox md.obsidian.Obsidian
  execute_root "Update flatpak" flatpak update -y
  execute "Install Zed" bash -c "curl -s -f https://zed.dev/install.sh | sh"
}

configure_dotfiles() {
  print_section "Configuring dotfiles..."
  touch "$HOME/.bashrc"
  local bash_init='eval "$(starship init bash)"'
  append_if_missing "$HOME/.bashrc" "starship init bash" "$bash_init"
  for src in "${!CFGS[@]}"; do
    IFS='|' read -r dest desc <<< "${CFGS[$src]}"
    copy_file "$src" "$dest" "${desc:-Config}"
  done
}

post_install() {
  print_section "Finalizing Setup..."
  execute_root "Generate AKMODS key" /usr/sbin/kmodgenca -a
  execute_root "Import MOK key" bash -c "
    printf 'password\npassword\n' | \\
      mokutil --import /etc/pki/akmods/certs/public_key.der || true
  "
  execute_root "Remove orphaned packages" dnf autoremove -y -q
  print_warning "Reboot required for NVIDIA. MOKManager password: 'password'"
}

show_help() {
  printf "Usage:\n  -h, --help\n  -d, --dotfiles-dir <dir>\n  --no-sudo\n  --debug\n"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dotfiles-dir)
        shift; [[ $# -ne 0 ]] && export DOTFILES_DIR="$1" || print_error "Dir req."
        ;;
      --no-sudo) USE_SUDO="false" ;;
      --debug) export DEBUG="true" ;;
      -h|--help) show_help; exit 0 ;;
      *) print_error "Unrecognized arg: '$1'." ;;
    esac
    shift
  done
}

main() {
  [[ "${DEBUG}" == "true" ]] && set -x
  trap '[[ $? -eq 0 ]] || print_error "Setup aborted unexpectedly."' EXIT

  if [[ -f "$DOTFILES_DIR/header.txt" ]]; then
    cat "$DOTFILES_DIR/header.txt"
  fi

  init_os
  for tool in "${!DEPS[@]}"; do check_tool "$tool" "${DEPS[$tool]}"; done
  remove_default_bloat
  install_system_packages
  install_hardware_drivers
  install_apps
  configure_dotfiles
  post_install
}

parse_args "$@"
main
