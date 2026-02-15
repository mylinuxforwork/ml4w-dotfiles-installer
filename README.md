# ML4W Dotfiles Installer

An authentic, modular, and safe way to deploy Linux configurations. This script acts as a professional **Profile Manager** that allows you to manage multiple dotfile setups, handles distribution-specific dependencies for **Arch**, **Fedora**, and **openSUSE**, and uses an intelligent symlinking system with automated backups.

## 🚀 Key Features

* **Modular Architecture:** Logic is separated into library files (`.local/share/ml4w-dots-installer/`) for easy maintenance.
* **Distro Agnostic:** Detects your package manager (Pacman, DNF, or Zypper) and handles dependencies accordingly.
* **Safe Sandbox:** Dotfiles are first copied to a local folder before being symlinked to `$HOME`.
* **Automated Backups:** Existing files are backed up with a timestamp before being replaced by symlinks.
* **AUR Helper Fallback:** On Arch, it intelligently checks for `yay`, then `paru`, then `pacman`.
* **Interactive TUI:** Uses `gum` for confirmations and professional terminal feedback.

---

## 🛠 Installation

To install the installer script to your local system:

1.  **Clone the repository.**
2.  **Run the installation:**
    ```bash
    make install
    ```
3.  **Ensure your PATH includes local bins:**
    Make sure `~/.local/bin` is in your environment `$PATH`.

---

## 📖 Usage

To install a dotfiles profile using a `.dotinst` URL:

```bash
ml4w-dotfiles-installer --install [https://raw.githubusercontent.com/user/repo/main/profile.dotinst](https://raw.githubusercontent.com/user/repo/main/profile.dotinst)

```

### Optional Parameters

* `--target <path>`: Overwrite the default storage location (Default: `~/.mydotfiles-test`).
* `--help`: Show the help menu.

---

## 🏗 For Content Creators: The `.dotinst` File

The installer parses a JSON-formatted `.dotinst` file to understand how to handle the repository.

### Template

```json
{
  "name": "My Hyprland Setup",
  "id": "hyprland-stable",
  "version": "1.0.0",
  "author": "YourName",
  "homepage": "[https://github.com/youruser/yourrepo](https://github.com/youruser/yourrepo)",
  "description": "A clean, dark-themed Hyprland configuration.",
  "source": "[https://github.com/youruser/yourrepo.git](https://github.com/youruser/yourrepo.git)",
  "tag": "v1.0"
}

```

### Required Repository Structure

Your Git repository must follow this structure for the automated logic to work:

```text
your-repo/
├── dotfiles/               # Contents are copied to ~/.mydotfiles-test/ID/
│   ├── .config/            # Folders inside are symlinked to ~/.config/
│   └── .zshrc              # Files are symlinked to $HOME/
└── setup/
    └── dependencies/
        ├── packages        # List of common packages
        ├── packages-arch   # Arch-specific packages
        ├── packages-fedora # Fedora-specific packages
        └── preflight-arch.sh # Prep script (e.g., to install AUR helpers)

```

---

## 🚫 The Blacklist Feature

To allow users to modify configuration files in their local test directory without losing those changes during a repository update, the installer supports a **Blacklist**.

* **Location:** `~/.config/ml4w-dotfiles-installer/<PROFILE_ID>/blacklist`
* **Functionality:** Any file or directory listed in this file will NOT be overwritten when files are copied from the temporary clone to your target folder (`~/.mydotfiles-test/<PROFILE_ID>`).
* **Recursive Protection:** If a folder is blacklisted, the folder and all its subfolders and files are preserved.

**Example blacklist content:**

```text
.zshrc
.config/waybar/launch.sh
.config/nvim

```

---

## 🛡 Safety & Backups

The installer uses a "Non-Destructive" symlinking approach:

1. **Backup:** If a real file or folder exists where a symlink needs to go, it is moved to `~/.mydotfiles-test/backups/YYYYMMDD_HHMMSS/`.
2. **Relative Links:** Symlinks are created using relative paths, making the profile folder portable.
3. **Config Isolation:** Instead of symlinking the entire `.config` folder, the script iterates through sub-folders to ensure existing app settings are not deleted.

---

## 🤝 Contributing

The logic is separated into `utils.sh` and `colors.sh`. Feel free to add new utility functions or installation modules.
