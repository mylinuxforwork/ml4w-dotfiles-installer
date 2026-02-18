# ML4W Dotfiles Installer

An authentic, modular, and safe way to deploy Linux configurations. This script acts as a professional **Profile Manager** that allows you to manage multiple dotfile setups, handles distribution-specific dependencies for **Arch**, **Fedora**, and **openSUSE**, and uses an intelligent symlinking system with automated backups.

## 🚀 Key Features

* **Distro Agnostic:** Detects your package manager (Pacman, DNF, or Zypper) automatically.
* **Safe Sandbox:** Dotfiles are first copied to a local folder before being symlinked to `$HOME`.
* **Proactive Symlinking:** Automatically detects if a symlink points to a different ID and replaces it.
* **Automated Backups:** Full profile snapshots and symlink backups organized by Project ID and Timestamp.
* **Developer Friendly:** Supports local `.dotinst` files and local repository sources for rapid testing.
* **Test Mode:** Verify package installation and setup logic without touching your files.
* **User Overrides:** Support for individual user `post.sh` scripts per profile.

---

## 🛠 Installation

To install the installer script to your local system:

1. **Clone the repository.**
2. **Run the installation:**
```bash
make install

```


3. **Ensure your PATH includes local bins:**
Make sure `~/.local/bin` is in your environment `$PATH`.

---

## 📖 Usage

### Standard Installation (Remote)

To install a dotfiles profile using a remote URL:

```bash
ml4w-dotfiles-installer --install https://raw.githubusercontent.com/user/repo/main/profile.dotinst

```

### Developer Installation (Local)

To test a local configuration file during development:

```bash
ml4w-dotfiles-installer --install ~/Projects/dotfiles/dev.dotinst

```

### 🧪 Test Mode (Setup Only)

Run the entire installation process—including package installation and pre/post scripts—without staging files or creating symlinks in your home directory. This is ideal for testing dependency logic on new distros:

```bash
ml4w-dotfiles-installer --install ~/Projects/dotfiles/dev.dotinst --testmode

```

---

## 🏗 For Content Creators: The `.dotinst` File

### Remote Profile Example (Production)

```json
{
  "name": "ML4W Hyprland Stable",
  "id": "com.ml4w.hyprland",
  "version": "2.10.1",
  "author": "Stephan Raabe",
  "homepage": "https://ml4w.com",
  "source": "https://github.com/mylinuxforwork/dotfiles.git",
  "subfolder": "dotfiles",
  "restore": [
    {
      "title": "Hyprland Settings",
      "source": ".config/hypr/settings.conf"
    }
  ]
}

```

---

## 🛠 Advanced Customization

### 1. Personal Overrides (User post.sh)

Users can define their own personal post-installation steps that run after the repository's standard scripts. This allows for system-specific tweaks (like enabling local services or setting hardware-specific drivers) without modifying the original dotfiles.

**To add an override:**

1. Create the profile config folder: `mkdir -p ~/.config/ml4w-dotfiles-installer/[PROFILE_ID]`
2. Create your script: `nano ~/.config/ml4w-dotfiles-installer/[PROFILE_ID]/post.sh`
3. Make it executable: `chmod +x ~/.config/ml4w-dotfiles-installer/[PROFILE_ID]/post.sh`

The installer will detect this script and run it at the very end of the setup logic.

### 2. Blacklist (File Preservation)

The blacklist allows you to prevent specific files in a profile from being overwritten during an update. This is useful for configuration files you want to manage manually or keep strictly local.

**Example:**
To prevent the installer from overwriting your local monitor setup or a specific theme file, add them to `~/.config/ml4w-dotfiles-installer/[PROFILE_ID]/blacklist`:

```text
# Blacklist Example
.config/hypr/conf/monitors.conf
.config/waybar/style.css
# You can also blacklist entire directories
.config/my-private-app/

```

Files listed here will be skipped during the staging process, preserving your local versions.

---

## 🔄 Restore & Update Logic

1. **Automatic Profile Backup:** Before updates, your profile folder is backed up to `~/.mydotfiles-test/backups/profile-updates/ID/<timestamp>`.
2. **Selective Restoration:** Interactive menu via `gum` to select which custom configurations to keep.
3. **Intelligent Merge:** Selected items are merged into the new source before deployment.

---

## 🛡 Safety & Backups

The installer uses a highly organized backup system:

1. **Symlink Backups:** If a file in `$HOME` is replaced, it is moved to `~/.mydotfiles-test/backups/[PROJECT_ID]/[TIMESTAMP]`.
2. **Active Replacement:** If the installer detects an existing symlink pointing to a *different* project ID, it proactively recreates the link to point to the currently active profile.

---

## 🤝 Contributing

The logic is separated into `utils.sh` and `colors.sh`. Feel free to add new utility functions or installation modules.