# Dotfiles

A simple, automated setup script for my Fedora development environment.

## Features

- **System Cleanup**: Removes default bloatware and unnecessary pre-installed packages.
- **CLI Utilities**: Installs `gh` and `just`.
- **Prompt**: Installs the `starship` prompt.
- **Typography**: Installs and caches FiraCode Nerd Font.
- **NVIDIA GPU**: Configures RPM Fusion, proprietary NVIDIA drivers, and the NVIDIA Container Toolkit.
- **Applications**: Installs Firefox, Obsidian, and the Zed editor.

## Usage

Clone the repository and execute the setup script:

```bash
git clone https://github.com/elijahcuellar/dotfiles.git ~/dotfiles
cd ~/dotfiles
./setup.sh
```

### Options

| Option | Description |
| :--- | :--- |
| `-d, --dotfiles-dir <dir>` | Specify a custom path to the dotfiles directory (default: `.`) |
| `--no-sudo` | Execute commands without `sudo` privileges |
| `--debug` | Enable verbose execution output |
| `-h, --help` | Display the help menu |

## Post-Install

Systems with **Secure Boot** enabled require a reboot to enroll the generated AKMODS key.

After rebooting, verify the key enrollment:

```bash
mokutil --test-key /etc/pki/akmods/certs/public_key.der
```

## Structure

- `setup.sh`: The primary provisioning script.
- `starship.toml`: Starship prompt configuration.
- `settings.json`: Zed editor configuration.
