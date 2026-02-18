#!/usr/bin/env bash

# --- UI Functions (Redirected to stderr) ---
info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

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

# --- Profile Backup ---
backup_existing_profile() {
    local profile_dir=$1; local id=$2; local backup_root=$3
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$backup_root/backups/profile-updates/$id/$timestamp"

    info "Backing up current profile state to $backup_path..."
    mkdir -p "$(dirname "$backup_path")"
    if cp -a "$profile_dir" "$backup_path"; then
        info "  - Backup completed successfully."
    else
        warn "  - Backup failed! Proceeding with caution..."
    fi
}

# --- Restore Orchestrator ---
handle_restore_logic() {
    local json=$1; local existing_dir=$2; local temp_dir=$3; local subfolder=$4
    local restore_data=$(echo "$json" | jq -r '.restore[] | "\(.title) [\(.source)]"' 2>/dev/null)
    if [ -z "$restore_data" ]; then return 0; fi

    local selected_default=$(echo "$restore_data" | paste -sd "," -)
    
    info "Existing configuration found. Select items to keep (RESTORE):"
    info "  [X] Selected: Keep your current local version"
    info "  [ ] Unchecked: Overwrite with the default version from the update"

    # Interaction Fix: Pipe data in, but tell gum to use TTY for interaction
    # Do NOT redirect standard output (stdout) to TTY here, or the variable will be empty
    local user_selections=$(echo "$restore_data" | gum choose --no-limit --selected="$selected_default" < /dev/tty)

    if [ -z "$user_selections" ]; then
        warn "No items selected for restoration. Updating with all default versions."
        return 0
    fi

    info "Merging custom configurations..."
    while IFS= read -r selection; do
        [[ -z "$selection" ]] && continue
        local title=$(echo "$selection" | sed 's/ \[.*\]$//' | xargs)
        local rel_src=$(echo "$json" | jq -r ".restore[] | select(.title==\"$title\") | .source")
        
        # Source is our currently installed folder
        local src_path="$existing_dir/$rel_src"
        
        # Destination is the temporary clone (so it is preserved during final deployment)
        local dest_path
        if [ -n "$subfolder" ] && [ "$subfolder" != "null" ]; then
            dest_path="$temp_dir/$subfolder/$rel_src"
        else
            dest_path="$temp_dir/$rel_src"
        fi

        if [ -e "$src_path" ]; then
            info "  - Restoring: $title ($rel_src)"
            mkdir -p "$(dirname "$dest_path")"
            cp -a "$src_path" "$dest_path"
        fi
    done <<< "$user_selections"
}

# --- RECURSIVE Blacklist-Aware Copy ---
copy_with_blacklist() {
    local source=$1; local target=$2; local blacklist=$3
    mkdir -p "$target"; info "Staging files to $target..."
    local blacklisted=()
    if [ -f "$blacklist" ]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(echo "$line" | xargs); [[ -z "$line" || "$line" =~ ^# ]] && continue
            blacklisted+=("$line")
        done < "$blacklist"
    fi

    cd "$source" || return 1
    find . -mindepth 1 | while read -r item; do
        local rel_path="${item#./}"; local target_path="$target/$rel_path"; local skip=false
        for b in "${blacklisted[@]}"; do
            if [[ "$rel_path" == "$b" ]] || [[ "$rel_path" == "$b"/* ]]; then skip=true; break; fi
        done
        if [ "$skip" = true ] && [ -e "$target_path" ]; then continue; fi
        if [ -d "$item" ]; then mkdir -p "$target_path"
        elif [ -f "$item" ]; then mkdir -p "$(dirname "$target_path")"; cp -a "$item" "$target_path"; fi
    done
}

# --- Symlink Helper ---
create_symlink() {
    local source=$1; local target=$2; local backup_dir=$3
    local abs_source=$(realpath -m "$source")

    # Aggressive Refresh: Always remove the existing link/file to ensure a refresh
    if [ -L "$target" ]; then
        rm "$target"
    elif [ -e "$target" ]; then
        warn "  - Existing file/folder found at $target. Creating backup..."
        mkdir -p "$backup_dir"; cp -a "$target" "$backup_dir/"; rm -rf "$target"
    fi

    info "  - Linking $target -> $source"
    ln -s --relative "$source" "$target"
}

# --- Deployment Orchestrator ---
deploy_symlinks() {
    local source_dir=$1; local backup_root=$2; local id=$3
    local timestamp=$(date +%Y%m%d_%H%M%S); local backup_dir="$backup_root/backups/$id/$timestamp"
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
    info "Deployment complete. Backups: $backup_dir"
}

get_distro_by_bin() {
    if command -v pacman &> /dev/null; then echo "arch"
    elif command -v dnf &> /dev/null; then echo "fedora"
    elif command -v zypper &> /dev/null; then echo "opensuse"
    else echo "unknown"; fi
}

install_package() {
    local pkg=$1; local distro=$(get_distro_by_bin)
    case "$distro" in
        arch) if command -v yay &> /dev/null; then yay -S --needed --noconfirm "$pkg"
              elif command -v paru &> /dev/null; then paru -S --needed --noconfirm "$pkg"
              else sudo pacman -S --needed --noconfirm "$pkg"; fi ;;
        fedora) sudo dnf install -y "$pkg" ;;
        opensuse) sudo zypper install -y "$pkg" ;;
    esac
}

process_package_file() {
    local file=$1; [ ! -f "$file" ] && return 0
    local distro=$(get_distro_by_bin)
    info "Processing package list: $(basename "$file")"
    while IFS= read -r pkg || [ -n "$pkg" ]; do
        pkg=$(echo "$pkg" | sed 's/#.*//' | xargs); [[ -z "$pkg" ]] && continue
        local installed=false
        case "$distro" in
            arch) pacman -Qi "$pkg" &> /dev/null && installed=true ;;
            fedora|opensuse) rpm -q "$pkg" &> /dev/null && installed=true ;;
        esac
        [ "$installed" = false ] && command -v "$pkg" &> /dev/null && installed=true
        if [ "$installed" = true ]; then info "  - $pkg is already installed. Skipping."
        else info "  - Installing $pkg..."; install_package "$pkg"; fi
    done < "$file"
}

run_setup_logic() {
    local repo_path=$1; local profile_id=$2; local distro=$(get_distro_by_bin)
    local dep_dir="$repo_path/setup/dependencies"
    local user_config_dir="$HOME/.config/ml4w-dotfiles-installer/$profile_id"
    
    local preflight="$repo_path/setup/preflight-$distro.sh"
    [ -f "$preflight" ] && { info "Running preflight script for $distro..."; bash "$preflight"; }
    
    if [ -d "$dep_dir" ]; then
        [ -f "$dep_dir/packages" ] && process_package_file "$dep_dir/packages"
        [ -f "$dep_dir/packages-$distro" ] && process_package_file "$dep_dir/packages-$distro"
    fi

    local postflight="$repo_path/setup/post-$distro.sh"
    [ -f "$postflight" ] && { info "Running post-installation script for $distro..."; bash "$postflight"; }

    local user_post="$user_config_dir/post.sh"
    [ -f "$user_post" ] && { info "Running user-specific post-installation script for $profile_id..."; bash "$user_post"; }
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
    read -r response < /dev/tty
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then 
        eval "$install_cmd"; hash -r 2>/dev/null
    else 
        error "Required tool $pkg missing. Exiting."; exit 1; fi
}

check_dependencies() {
    info "Checking system dependencies..."
    check_and_install "make" "make"; check_and_install "git" "git"
    check_and_install "curl" "curl"; check_and_install "jq" "jq"
    check_and_install "gum" "gum"
}

read_dotinst() {
    local source=$1; local target_base_dir=$2; local test_mode=$3
    local content=$(get_json_content "$source")
    [ $? -ne 0 ] || [ -z "$content" ] && { error "Failed to read configuration."; return 1; }

    local name=$(echo "$content" | jq -r '.name // "Unknown Profile"')
    local id=$(echo "$content" | jq -r '.id // "N/A"')
    local author=$(echo "$content" | jq -r '.author // "N/A"')
    local homepage=$(echo "$content" | jq -r '.homepage // "N/A"')
    local version=$(echo "$content" | jq -r '.version // "N/A"')
    local tag=$(echo "$content" | jq -r '.tag // empty')
    local description=$(echo "$content" | jq -r '.description // "No description provided."')
    local git_url_raw=$(echo "$content" | jq -r '.source // empty')
    local subfolder=$(echo "$content" | jq -r '.subfolder // empty')
    
    local git_url="${git_url_raw/\$HOME/$HOME}"; git_url="${git_url/\~/$HOME}"
    local user_post="$HOME/.config/ml4w-dotfiles-installer/$id/post.sh"

    local install_type_text="${GREEN}New Installation${NC}"
    [ -d "$target_base_dir/$id" ] && install_type_text="${YELLOW}Update of existing configuration${NC}"

    echo -e "${GREEN}--------------------------------------------------${NC}" >&2
    echo -e "${YELLOW}PROFILE INFORMATION${NC}" >&2
    [ "$test_mode" = true ] && echo -e "Mode:        ${RED}TEST MODE (Setup only)${NC}" >&2
    echo -e "Status:      $install_type_text" >&2
    echo -e "Name:        $name" >&2
    echo -e "ID:          $id" >&2
    echo -e "Version:     $version" >&2
    [ -n "$tag" ] && [ "$tag" != "null" ] && echo -e "Tag:         $tag" >&2
    echo -e "Author:      $author" >&2
    echo -e "Homepage:    $homepage" >&2
    echo -e "Source:      $git_url" >&2
    [ -n "$subfolder" ] && [ "$subfolder" != "null" ] && echo -e "Subfolder:   $subfolder" >&2
    
    if [ -f "$user_post" ]; then
        echo -e "User Script: ${GREEN}Detected${NC}" >&2
    else
        echo -e "User Script: None" >&2
    fi
    echo -e "Description: $description" >&2
    echo -e "${GREEN}--------------------------------------------------${NC}" >&2

    if ! gum confirm "Do you want to proceed with the installation?" < /dev/tty > /dev/tty; then 
        info "Installation cancelled by user."; exit 0; fi

    local working_dir=$(mktemp -d -t ml4w-dots-XXXXXX)
    if [ -d "$git_url" ]; then
        info "Local repository detected. Copying source..."
        cp -a "$git_url/." "$working_dir/"
    else
        info "Remote repository detected. Cloning source..."
        local clone_cmd="git clone --depth=1"
        [ -n "$tag" ] && [ "$tag" != "null" ] && clone_cmd="git clone --depth=1 --branch $tag"
        if ! $clone_cmd "$git_url" "$working_dir" &> /dev/null; then 
            error "Failed to clone repository."; rm -rf "$working_dir"; return 1
        fi
    fi
    printf "%s %s %s" "$working_dir" "$id" "$subfolder"
}