# ML4W Dotfiles Installer

An authentic, modular, and safe way to deploy Linux configurations. This script acts as a professional **Profile Manager** that allows you to manage multiple dotfile setups, handles distribution-specific dependencies for **Arch**, **Fedora**, and **openSUSE**, and uses an intelligent symlinking system with automated backups.

## 🚀 Key Features

* **Modular Architecture:** Logic is separated into library files for easy maintenance.
* **Distro Agnostic:** Detects your package manager (Pacman, DNF, or Zypper) automatically.
* **Safe Sandbox:** Dotfiles are first copied to a local folder before being symlinked to `$HOME`.
* **Proactive Symlinking:** Automatically detects if a symlink points to a different ID and replaces it.
* **Automated Backups:** Full profile snapshots and symlink backups organized by Project ID and Timestamp.
* **Developer Friendly:** Supports local `.dotinst` files and local repository sources for rapid testing.

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

---

## 🏗 For Content Creators: The `.dotinst` File

The installer parses a JSON-formatted `.dotinst` file.

### Local Source Support (for Developers)

In the `source` field, you can specify a local directory instead of a Git URL. The script supports variable expansion for `$HOME` and `~`.

```json
{
  "name": "My Dev Setup",
  "id": "com.user.dev",
  "version": "1.0.0",
  "author": "Developer Name",
  "source": "$HOME/Projects/my-dotfiles-repo",
  "subfolder": "dotfiles",
  "restore": [
    {
      "title": "Local Settings",
      "source": ".config/myapp/settings.conf"
    }
  ]
}

```

### Required Repository Structure

Your repository (local or remote) should follow this structure:

```text
your-repo/
├── dotfiles/               # Contents (or the defined "subfolder") are copied to ~/.mydotfiles-test/ID/
│   ├── .config/            # Folders inside are symlinked to ~/.config/
│   └── .zshrc              # Files are symlinked to $HOME/
└── setup/
    └── dependencies/
        ├── packages        # Common packages
        └── packages-arch   # Distro-specific packages

```

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