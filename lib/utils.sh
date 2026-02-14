#!/usr/bin/env bash

# --- Utility Functions (Redirected to stderr) ---
info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

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

# --- Core Package Installation Engine ---
# Handles the specific logic for Arch (AUR helpers), Fedora, and openSUSE
install_package() {
    local pkg=$1
    local distro=$(get_distro_by_bin)

    case "$distro" in
        arch)
            if command -v yay &> /dev/null; then
                yay -S --needed --noconfirm "$pkg"
            elif command -v paru &> /dev/null; then
                paru -S --needed --noconfirm "$pkg"
            else
                sudo pacman -S --needed --noconfirm "$pkg"
            fi
            ;;
        fedora)
            sudo dnf install -y "$pkg"
            ;;
        opensuse)
            sudo zypper install -y "$pkg"
            ;;
    esac
}

# --- Package List Processor ---
# Reads a file and installs packages if they aren't already on the system
process_package_file() {
    local file=$1
    [ ! -f "$file" ] && return 0

    info "Processing package list: $(basename "$file")"
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        # Strip comments and empty lines
        pkg=$(echo "$pkg" | sed 's/#.*//' | xargs)
        [[ -z "$pkg" ]] && continue

        # Check if already installed
        if command -v "$pkg" &> /dev/null || pacman -Qi "$pkg" &> /dev/null 2>&1 || rpm -q "$pkg" &> /dev/null 2>&1; then
            info "  - $pkg is already installed. Skipping."
        else
            info "  - Installing $pkg..."
            install_package "$pkg"
        fi
    done < "$file"
}

# --- Dependency Orchestrator ---
# Manages Preflight -> Common Packages -> Distro Packages
run_setup_logic() {
    local repo_path=$1
    local distro=$(get_distro_by_bin)
    local dep_dir="$repo_path/setup/dependencies"

    if [ ! -d "$dep_dir" ]; then
        warn "No dependency folder found at $dep_dir. Skipping package installation."
        return 0
    fi

    # 1. Execute Preflight (Distro specific preparation)
    local preflight="$dep_dir/preflight-$distro.sh"
    if [ -f "$preflight" ]; then
        info "Running preflight script for $distro..."
        bash "$preflight"
    fi

    # 2. Install Common Packages
    if [ -f "$dep_dir/packages" ]; then
        process_package_file "$dep_dir/packages"
    fi

    # 3. Install Distro-Specific Packages
    local distro_pkgs="$dep_dir/packages-$distro"
    if [ -f "$distro_pkgs" ]; then
        process_package_file "$distro_pkgs"
    fi
}

# --- Core Tool Check (Used before cloning) ---
check_and_install() {
    local cmd=$1
    local pkg=$2
    local distro=$(get_distro_by_bin)

    if command -v "$cmd" &> /dev/null; then
        return 0
    fi

    warn "✗ $cmd is not installed."
    case "$distro" in
        arch)     install_cmd="sudo pacman -S --needed --noconfirm $pkg" ;;
        fedora)   install_cmd="sudo dnf install -y $pkg" ;;
        opensuse) install_cmd="sudo zypper install -y $pkg" ;;
        *)        error "Unsupported distro. Please install $pkg manually."; return 1 ;;
    esac

    echo -n -e "${YELLOW}Do you want to install $pkg now? (y/n): ${NC}" >&2
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "Installing $pkg..."
        eval "$install_cmd"
    else
        error "$pkg is required. Exiting."
        exit 1
    fi
}

check_dependencies() {
    info "Checking system dependencies..."
    check_and_install "make" "make"
    check_and_install "git" "git"
    check_and_install "curl" "curl"
    check_and_install "jq" "jq"
    check_and_install "gum" "gum"
}

# --- Dotinst Reader & Cloner ---
read_dotinst() {
    local url=$1
    content=$(curl -sL "$url")
    if [ $? -ne 0 ]; then return 1; fi

    local git_url=$(echo "$content" | jq -r '.source // empty')
    local install_script=$(echo "$content" | jq -r '.install // "install.sh"')
    local working_dir=$(mktemp -d -t ml4w-dots-XXXXXX)
    
    if git clone --depth=1 "$git_url" "$working_dir" &> /dev/null; then
        echo "$working_dir $install_script"
    else
        rm -rf "$working_dir"
        return 1
    fi
}