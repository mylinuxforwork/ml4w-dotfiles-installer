#!/usr/bin/env bash

# --- UI Functions (Redirected to stderr) ---
info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- RECURSIVE Blacklist-Aware Copy ---
copy_with_blacklist() {
    local source=$1
    local target=$2
    local blacklist=$3

    mkdir -p "$target"
    info "Deploying files to $target..."

    local blacklisted=()
    if [ -f "$blacklist" ]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(echo "$line" | xargs)
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            blacklisted+=("$line")
        done < "$blacklist"
        info "  - Active blacklist found with ${#blacklisted[@]} items."
    fi

    # Iterate over EVERY file and directory in the source
    cd "$source" || return 1
    find . -mindepth 1 | while read -r item; do
        local rel_path="${item#./}"
        local target_path="$target/$rel_path"
        
        # Check if this path or ANY of its parent directories are blacklisted
        local skip=false
        for b in "${blacklisted[@]}"; do
            # Case 1: Direct match (file or folder)
            # Case 2: The item is inside a blacklisted folder (prefix match)
            if [[ "$rel_path" == "$b" ]] || [[ "$rel_path" == "$b"/* ]]; then
                skip=true
                break
            fi
        done

        if [ "$skip" = true ] && [ -e "$target_path" ]; then
            # Only warn for the top-level blacklisted item to avoid log spam
            if [[ "$rel_path" == "$b" ]]; then
                warn "  - Preserving blacklisted entry: $rel_path"
            fi
            continue
        fi

        if [ -d "$item" ]; then
            mkdir -p "$target_path"
        elif [ -f "$item" ]; then
            mkdir -p "$(dirname "$target_path")"
            cp -a "$item" "$target_path"
        fi
    done
}

# --- Symlink Helper ---
create_symlink() {
    local source=$1
    local target=$2
    local backup_dir=$3

    if [ -L "$target" ]; then
        info "  - Symlink already exists for $(basename "$target"). Skipping."
        return 0
    fi

    if [ -e "$target" ]; then
        warn "  - Existing file/folder found at $target. Creating backup..."
        mkdir -p "$backup_dir"
        cp -a "$target" "$backup_dir/"
        rm -rf "$target"
    fi

    info "  - Linking $target -> $source"
    ln -s --relative "$source" "$target"
}

# --- Deployment Orchestrator ---
deploy_symlinks() {
    local source_dir=$1
    local backup_root=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$backup_root/backups/$timestamp"

    info "Starting symlink deployment..."

    for item in "$source_dir"/* "$source_dir"/.*; do
        local name=$(basename "$item")
        [[ "$name" == "." || "$name" == ".." || "$name" == ".config" ]] && continue
        [ -e "$item" ] || continue
        
        create_symlink "$item" "$HOME/$name" "$backup_dir"
    done

    if [ -d "$source_dir/.config" ]; then
        mkdir -p "$HOME/.config"
        for item in "$source_dir/.config"/* "$source_dir/.config"/.*; do
            local name=$(basename "$item")
            [[ "$name" == "." || "$name" == ".." ]] && continue
            [ -e "$item" ] || continue
            
            create_symlink "$item" "$HOME/.config/$name" "$backup_dir"
        done
    fi

    info "Symlink deployment complete. Backups (if any) are in $backup_dir"
}

get_distro_by_bin() {
    if command -v pacman &> /dev/null; then echo "arch";
    elif command -v dnf &> /dev/null; then echo "fedora";
    elif command -v zypper &> /dev/null; then echo "opensuse";
    else echo "unknown"; fi
}

install_package() {
    local pkg=$1
    local distro=$(get_distro_by_bin)
    case "$distro" in
        arch)
            if command -v yay &> /dev/null; then yay -S --needed --noconfirm "$pkg"
            elif command -v paru &> /dev/null; then paru -S --needed --noconfirm "$pkg"
            else sudo pacman -S --needed --noconfirm "$pkg"; fi ;;
        fedora) sudo dnf install -y "$pkg" ;;
        opensuse) sudo zypper install -y "$pkg" ;;
    esac
}

process_package_file() {
    local file=$1
    [ ! -f "$file" ] && return 0
    info "Processing package list: $(basename "$file")"
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        pkg=$(echo "$pkg" | sed 's/#.*//' | xargs)
        [[ -z "$pkg" ]] && continue
        if command -v "$pkg" &> /dev/null || pacman -Qi "$pkg" &> /dev/null 2>&1 || rpm -q "$pkg" &> /dev/null 2>&1; then
            info "  - $pkg is already installed. Skipping."
        else
            info "  - Installing $pkg..."
            install_package "$pkg"
        fi
    done < "$file"
}

run_setup_logic() {
    local repo_path=$1
    local distro=$(get_distro_by_bin)
    local dep_dir="$repo_path/setup/dependencies"
    if [ ! -d "$dep_dir" ]; then warn "Dependency folder not found at: $dep_dir"; return 1; fi
    local preflight="$dep_dir/preflight-$distro.sh"
    if [ -f "$preflight" ]; then info "Running preflight script for $distro..."; bash "$preflight"; fi
    [ -f "$dep_dir/packages" ] && process_package_file "$dep_dir/packages"
    local distro_pkgs="$dep_dir/packages-$distro"
    [ -f "$distro_pkgs" ] && process_package_file "$dep_dir/packages-$distro"
}

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
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then eval "$install_cmd"
    else error "Required tool $pkg missing. Exiting."; exit 1; fi
}

check_dependencies() {
    info "Checking system dependencies..."
    check_and_install "make" "make"
    check_and_install "git" "git"
    check_and_install "curl" "curl"
    check_and_install "jq" "jq"
    check_and_install "gum" "gum"
}

read_dotinst() {
    local url=$1
    local target_base_dir=$2
    local content=$(curl -sL "$url")
    if [ $? -ne 0 ] || [ -z "$content" ]; then error "Failed to download configuration."; return 1; fi
    local name=$(echo "$content" | jq -r '.name // "Unknown Profile"')
    local id=$(echo "$content" | jq -r '.id // "N/A"')
    local author=$(echo "$content" | jq -r '.author // "N/A"')
    local homepage=$(echo "$content" | jq -r '.homepage // "N/A"')
    local description=$(echo "$content" | jq -r '.description // "No description provided."')
    local version=$(echo "$content" | jq -r '.version // "N/A"')
    local tag=$(echo "$content" | jq -r '.tag // empty')
    local git_url=$(echo "$content" | jq -r '.source // empty')

    local install_type_text="${GREEN}New Installation${NC}"
    if [ -d "$target_base_dir/$id" ]; then
        install_type_text="${YELLOW}Update of existing configuration${NC}"
    fi

    echo -e "${GREEN}--------------------------------------------------${NC}" >&2
    echo -e "${YELLOW}PROFILE INFORMATION${NC}" >&2
    echo -e "Status:      $install_type_text" >&2
    echo -e "Name:        $name" >&2
    echo -e "ID:          $id" >&2
    echo -e "Version:     $version" >&2
    [ -n "$tag" ] && [ "$tag" != "null" ] && echo -e "Tag:         $tag" >&2
    echo -e "Author:      $author" >&2
    echo -e "Homepage:    $homepage" >&2
    echo -e "Description: $description" >&2
    echo -e "${GREEN}--------------------------------------------------${NC}" >&2
    echo -e "Source URL:  $git_url" >&2
    echo -e "${GREEN}--------------------------------------------------${NC}" >&2

    if ! gum confirm "Do you want to proceed with the installation?"; then info "Installation cancelled by user."; exit 0; fi

    local working_dir=$(mktemp -d -t ml4w-dots-XXXXXX)
    local clone_cmd="git clone --depth=1"
    [ -n "$tag" ] && [ "$tag" != "null" ] && clone_cmd="git clone --depth=1 --branch $tag"

    info "Cloning repository..."
    if $clone_cmd "$git_url" "$working_dir" &> /dev/null; then printf "%s %s" "$working_dir" "$id"
    else error "Failed to clone repository."; rm -rf "$working_dir"; return 1; fi
}