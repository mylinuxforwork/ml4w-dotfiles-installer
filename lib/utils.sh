#!/usr/bin/env bash

# --- Utility Functions ---
# Note: These assume RED, GREEN, YELLOW, and NC are defined in colors.sh
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Distro Detection by Binary ---
get_distro_by_bin() {
    if command -v pacman &> /dev/null; then
        echo "arch"
    elif command -v dnf &> /dev/null; then
        echo "fedora"
    elif command -v zypper &> /dev/null; then
        echo "opensuse"
    else
        echo "unknown"
    fi
}

# --- Core Dependency Handler ---
# usage: check_and_install <command_name> <package_name>
check_and_install() {
    local cmd=$1
    local pkg=$2
    local distro
    distro=$(get_distro_by_bin)

    if command -v "$cmd" &> /dev/null; then
        info "✓ $cmd is already installed."
        return 0
    fi

    warn "✗ $cmd is not installed."
    
    # Define the install command based on distro
    case "$distro" in
        arch)     install_cmd="sudo pacman -S --needed $pkg" ;;
        fedora)   install_cmd="sudo dnf install $pkg" ;;
        opensuse) install_cmd="sudo zypper install $pkg" ;;
        *)        error "Unsupported distro. Please install $pkg manually."; return 1 ;;
    esac

    # Ask the user (Standard read used here because gum might not be installed yet!)
    echo -n -e "${YELLOW}Do you want to install $pkg now? (y/n): ${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "Installing $pkg..."
        eval "$install_cmd"
    else
        error "$pkg is required. Exiting."
        exit 1
    fi
}

# --- Main Dependency Check ---
check_dependencies() {
    info "Checking system dependencies..."
    
    # 1. Check for 'make' (The build tool)
    check_and_install "make" "make"
    
    # 2. Check for 'git' (To clone the dots)
    check_and_install "git" "git"
    
    # 3. Check for 'gum' (For the fancy UI)
    # Most modern repos (Arch Extra, Fedora, Tumbleweed) carry gum
    check_and_install "gum" "gum"
}