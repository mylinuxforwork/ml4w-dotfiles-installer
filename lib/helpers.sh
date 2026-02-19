#!/usr/bin/env bash

# --- Helper to identify the Linux distro ---
get_distro_by_bin() {
    if command -v pacman &> /dev/null; then echo "arch";
    elif command -v dnf &> /dev/null; then echo "fedora";
    elif command -v zypper &> /dev/null; then echo "opensuse";
    else echo "unknown"; fi
}

# --- Helper to check command and install if not available ---
check_and_install() {
    local cmd=$1; local pkg=$2; local distro=$(get_distro_by_bin)
    if command -v "$cmd" &> /dev/null; then return 0; fi
    
    warn "✗ $cmd is not installed."
    case "$distro" in
        arch) install_cmd="sudo pacman -S --needed --noconfirm $pkg" ;;
        fedora) install_cmd="sudo dnf install -y $pkg" ;;
        opensuse) install_cmd="sudo zypper install -y $pkg" ;;
        *) error "Unsupported distro."; return 1 ;;
    esac

    echo -n -e "${YELLOW}Do you want to install $pkg now? (y/n): ${NC}" >&2
    read -r response
    
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then 
        eval "$install_cmd"
    else 
        error "Required tool $pkg missing. Exiting."; exit 1
    fi
}

# --- Helper to install a package disto agnostic ---
install_package() {
    local pkg=$1; local distro=$(get_distro_by_bin)
    case "$distro" in
        arch)
            if command -v yay &> /dev/null; then yay -S --needed --noconfirm "$pkg"
            elif command -v paru &> /dev/null; then paru -S --needed --noconfirm "$pkg"
            else sudo pacman -S --needed --noconfirm "$pkg"; fi ;;
        fedora) sudo dnf install -y "$pkg" ;;
        opensuse) sudo zypper install -y "$pkg" ;;
    esac
}

# --- Helper to get content from URL or Local File ---
get_json_content() {
    local source=$1
    if [[ "$source" =~ ^https?:// ]]; then
        curl -sL "$source"
    elif [ -f "$source" ]; then
        cat "$source"
    else
        return 1
    fi
}
