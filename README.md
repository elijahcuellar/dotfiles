# Dotfiles

A simple, automated setup for my Fedora development environment. It is optimized for Wayland, NVIDIA GPUs, plus Podman containers.

## Features

The `setup.sh` script configures a fresh Fedora install with:

- **CLI Tools**: `gh`, `just`, `starship`
- **Fonts**: Fira Code
- **NVIDIA**: Proprietary drivers configured for Wayland
- **Podman**: GPU-accelerated containers
- **Desktop Apps**: Zed, Obsidian (Flatpak)
- **Dotfiles**: Custom configs for Starship, Zed

## Usage

Clone this repository, then run the setup script:

```bash
git clone https://github.com/elijahcuellar/dotfiles.git ~/dotfiles
cd ~/dotfiles
./setup.sh
```

### Options

The script supports a few flags:

- `-d, --dotfiles-dir <dir>`: Set a custom path to the dotfiles folder.
- `--no-sudo`: Run without `sudo` privileges.
- `--debug`: Show verbose debug output.
- `-h, --help`: Show the help menu.

## Structure

- `setup.sh`: The main installation script.
- `starship.toml`: Settings for the Starship prompt.
- `settings.json`: Settings for the Zed editor.