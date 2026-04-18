╔──────────────────────────────────────────────────────────╗
│░█▀▀░█▀▀░█▀▄░█▀█░█▀▄░█▀█░░░░░░░█▀▄░█▀▀░█▀▀░▀█▀░█▀█░█▀▀░█▀▄│
│░█▀▀░█▀▀░█░█░█░█░█▀▄░█▀█░░░░░░░█▀▄░█▀▀░█▀▀░░█░░█░█░█▀▀░█░█│
│░▀░░░▀▀▀░▀▀░░▀▀▀░▀░▀░▀░▀░▄▀░░░░▀░▀░▀▀▀░▀░░░▀▀▀░▀░▀░▀▀▀░▀▀░│
╚──────────────────────────────────────────────────────────╝

Welcome to my dotfiles! Here, you will find the configurations and automated script I use to personalize my Fedora development environment. From automated software installation to editor configurations, this repository contains a curated collection of my favorite tools and customizations designed to enhance productivity and streamline my workflow. Feel free to explore, fork, and contribute if you find something useful or have suggestions for improvements. Happy coding!

## Usage

This repository contains my automated setup script to configure Fedora Linux.

```bash
# Clone the repository
git clone https://github.com/elijahcuellar/dotfiles.git
cd dotfiles

# Run the setup script
bash setup.sh
```

### Options

- `-d, --dotfiles-dir <dir>`: Specify the location of the dotfiles directory.
- `--no-sudo`: Skip using `sudo` for commands (assumes you are already root or have permissions).
- `--debug`: Enable debug mode to print verbose trace logs and step output.
- `-h, --help`: Show help text.

## Features

- **Debloating:** Removes unnecessary pre-installed packages.
- **DNF Optimization:** Configures `dnf` with `fastestmirror` and parallel downloads.
- **Drivers:** Configures RPMFusion and sets up NVIDIA drivers and container toolkit.
- **Apps:** Installs Firefox, [Ghostty](https://ghostty.org/), [Apostrophe](https://apps.gnome.org/Apostrophe/), [Extension Manager](https://mattjakeman.com/apps/extension-manager), and [Zed](https://zed.dev/) editor.
- **CLI Tools:** Installs [Starship](https://starship.rs/), Git, [Just](https://just.systems/), [Micro](https://micro-editor.github.io/), [OneDrive](https://abraunegg.github.io/), and GitHub CLI.
- **Fonts:** Installs FiraCode Nerd Font.
