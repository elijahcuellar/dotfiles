░█░█░█▀▀░█░░░█▀▀░█▀█░█▄█░█▀▀░░░▀█▀░█▀█░░░█▀▀░█▀▀░█▀▄░█▀█░█▀▄░█▀█
░█▄█░█▀▀░█░░░█░░░█░█░█░█░█▀▀░░░░█░░█░█░░░█▀▀░█▀▀░█░█░█░█░█▀▄░█▀█
░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀▀▀░░░░▀░░▀▀▀░░░▀░░░▀▀▀░▀▀░░▀▀▀░▀░▀░▀░▀

Here, you'll find all the configurations and customizations that I use to make my development environment efficient and personalized. From terminal settings to editor configurations, this repository is a collection of my favorite tools and tweaks that enhance my workflow. Feel free to explore, fork, and contribute if you find something useful or have suggestions for improvements. Happy coding!

## Usage

This repository contains an automated setup script to configure a Fedora Linux environment.

```bash
# Clone the repository
git clone https://github.com/elijahcuellar/dotfiles.git
cd dotfiles

# Run the setup script
bash setup.sh
```

### Options

- `-d, --dotfiles-dir <dir>`: Specify the location of the dotfiles directory if running from elsewhere.
- `--no-sudo`: Skip using `sudo` for commands (assumes you are already root or have permissions).
- `--debug`: Enable debug mode to print verbose trace logs and step output directly to the terminal.
- `-h, --help`: Show help text.

## Features

- **System Tweaks:** Cleans default bloatware.
- **DNF Optimization:** Configures `dnf` with `fastestmirror` and parallel downloads.
- **Hardware Drivers:** Configures RPMFusion and sets up NVIDIA drivers + container toolkit securely.
- **Apps:** Installs Firefox, Obsidian, and Zed Editor.
- **CLI Tools:** Installs Starship, Git, Just, GitHub CLI, and FiraCode Nerd Font.
