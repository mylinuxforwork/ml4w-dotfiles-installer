#!/usr/bin/env bash

# --- Profile Backup ---
backup_existing_profile() {
    local profile_dir=$1
    local id=$2
    local backup_root=$3
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
    local json=$1
    local existing_dir=$2
    local temp_dir=$3
    local subfolder=$4

    local restore_data=$(echo "$json" | jq -r '.restore[] | "\(.title) [\(.source)]"' 2>/dev/null)
    
    if [ -z "$restore_data" ]; then
        return 0
    fi

    local selected_default=$(echo "$restore_data" | paste -sd "," -)
    
    info "Existing configuration found. Select items to keep (Restore):"
    info "Uncheck items to overwrite with default versions from the update."
    
    local user_selections
    if [ "${ML4W_YES:-0}" = "1" ]; then
        # Non-interactive: keep every item (default selection = all). Scripts
        # (dot-switch) set ML4W_YES=1; gum can't be answered with typed 'y'.
        user_selections="$restore_data"
    else
        user_selections=$(echo "$restore_data" | gum choose --no-limit --height 25 --selected="$selected_default")
    fi

    if [ -z "$user_selections" ]; then
        warn "No items selected for restoration. Overwriting with all defaults."
        return 0
    fi

    info "Merging custom configurations..."
    while IFS= read -r selection; do
        local title=$(echo "$selection" | sed 's/ \[.*\]$//')
        local rel_src=$(echo "$json" | jq -r ".restore[] | select(.title==\"$title\") | .source")
        
        local src_path="$existing_dir/$rel_src"
        
        local dest_path
        if [ -n "$subfolder" ] && [ "$subfolder" != "null" ]; then
            dest_path="$temp_dir/$subfolder/$rel_src"
        else
            dest_path="$temp_dir/$rel_src"
        fi

        if [ -e "$src_path" ]; then
            info "  - Restoring: $title ($rel_src)"
            mkdir -p "$(dirname "$dest_path")"
            # -T treats the destination as the target itself, never as a folder
            # to copy into. Without it an existing destination folder would
            # receive a nested copy (e.g. settings/settings) instead of a merge.
            cp -aT "$src_path" "$dest_path"
        else
            warn "  - Restore source not found: $rel_src"
        fi
    done <<< "$user_selections"
}

# --- Blacklist Matching Helper ---
# Returns 0 (true) if rel_path is blacklisted: exact match, path lives under
# a blacklisted entry, or path is an ancestor of one. The ancestor case
# matters for symlink deployment — if a subdirectory is blacklisted, its
# parent must not be linked either, otherwise a partial sandbox would replace
# real local files.
is_blacklisted() {
    local rel_path=$1
    local blacklist=$2
    [ -f "$blacklist" ] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | xargs)
        line="${line%/}"   # normalize trailing slash (README example: .config/my-app/)
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        [[ "$rel_path" == "$line" || "$rel_path" == "$line"/* || "$line" == "$rel_path"/* ]] && return 0
    done < "$blacklist"
    return 1
}

# --- RECURSIVE Blacklist-Aware Copy ---
copy_with_blacklist() {
    local source=$1
    local target=$2
    local blacklist=$3

    mkdir -p "$target"
    info "Staging files to $target..."

    local blacklisted=()
    if [ -f "$blacklist" ]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(echo "$line" | xargs)
            line="${line%/}"   # normalize trailing slash (README example: .config/my-app/)
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            blacklisted+=("$line")
        done < "$blacklist"
        info "  - Active blacklist found with ${#blacklisted[@]} items."
    fi

    cd "$source" || return 1
    find . -mindepth 1 | while read -r item; do
        local rel_path="${item#./}"
        local target_path="$target/$rel_path"
        
        local skip=false
        for b in "${blacklisted[@]}"; do
            if [[ "$rel_path" == "$b" ]] || [[ "$rel_path" == "$b"/* ]]; then
                skip=true
                break
            fi
        done

        # Skip blacklisted entries unconditionally. The previous guard
        # (`[ -e "$target_path" ]`) only preserved blacklisted paths that
        # already existed in the sandbox, so a fresh deploy staged them
        # anyway and they got symlinked over real files.
        if [ "$skip" = true ]; then
            if [[ "$rel_path" == "$b" ]]; then
                warn "  - Skipping blacklisted entry: $rel_path"
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
    local source=$1; local target=$2; local backup_dir=$3
    local abs_source=$(realpath -m "$source")

    if [ -L "$target" ]; then
        local current_link_target=$(realpath -m "$target")
        if [ "$current_link_target" == "$abs_source" ]; then
            info "  - Link already correct for $(basename "$target"). Skipping."
            return 0
        else
            warn "  - Link $(basename "$target") points elsewhere. Recreating..."
            rm "$target"
        fi
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
    local source_dir=$1; local backup_root=$2; local id=$3; local blacklist=$4
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$backup_root/backups/$id/$timestamp"

    info "Starting symlink deployment..."
    for item in "$source_dir"/* "$source_dir"/.*; do
        local name=$(basename "$item")
        [[ "$name" == "." || "$name" == ".." || "$name" == ".config" ]] && continue
        [ -e "$item" ] || continue

        # Never link blacklisted paths, even if they somehow exist in the
        # sandbox (e.g. staged by an older version or an empty dir).
        if is_blacklisted "$name" "$blacklist"; then
            warn "  - Skipping blacklisted entry: $name"
            continue
        fi

        create_symlink "$item" "$HOME/$name" "$backup_dir"
    done

    if [ -d "$source_dir/.config" ]; then
        mkdir -p "$HOME/.config"
        for item in "$source_dir/.config"/* "$source_dir/.config"/.*; do
            local name=$(basename "$item")
            [[ "$name" == "." || "$name" == ".." ]] && continue
            [ -e "$item" ] || continue

            if is_blacklisted ".config/$name" "$blacklist"; then
                warn "  - Skipping blacklisted entry: .config/$name"
                continue
            fi

            create_symlink "$item" "$HOME/.config/$name" "$backup_dir"
        done
    fi
    info "Symlink deployment complete."
    info "Backups are in $backup_dir"
}

# --- Process package list and install packages ---
process_package_file() {
    local file=$1; [ ! -f "$file" ] && return 0
    local distro=$(get_distro_by_bin)
    info "Processing package list: $(basename "$file")"

    # Read the list up front so install commands can't consume the loop's stdin
    local lines; mapfile -t lines < "$file"
    local pkg
    for pkg in "${lines[@]}"; do
        pkg=$(echo "$pkg" | sed 's/#.*//' | xargs); [[ -z "$pkg" ]] && continue

        local installed=false
        case "$distro" in
            arch)
                if pacman -Qi "$pkg" &> /dev/null; then installed=true; fi
                ;;
            fedora|opensuse)
                if rpm -q "$pkg" &> /dev/null; then installed=true; fi
                ;;
            ubuntu)
                if dpkg-query -W -f='${Status}' "$pkg" 2> /dev/null | grep -q "install ok installed"; then installed=true; fi
                ;;
        esac

        if [ "$installed" = false ] && command -v "$pkg" &> /dev/null; then
            installed=true
        fi

        if [ "$installed" = true ]; then
            info "  - $pkg is already installed. Skipping."
        elif install_package "$pkg"; then
            info "  ✓ $pkg installed."
        else
            error "  ✗ Failed to install $pkg."
            FAILED_PACKAGES+=("$pkg")
        fi
    done
}

# --- Run setup logic with preflight, dependencies, post-installation and user post script ---
run_setup_logic() {
    local repo_path=$1; local profile_id=$2
    local distro=$(get_distro_by_bin)
    local dep_dir="$repo_path/setup/dependencies"
    local user_config_dir="$HOME/.config/ml4w-dotfiles-installer/$profile_id"
    
    # 1. Repo Preflight (general first, then distro-specific)
    local preflight="$repo_path/setup/preflight.sh"
    if [ -f "$preflight" ]; then
        info "Running preflight script $preflight..."
        source "$preflight"
    fi
    local distro_preflight="$repo_path/setup/preflight-$distro.sh"
    if [ -f "$distro_preflight" ]; then 
        info "Running preflight script $distro_preflight for $distro..."
        source "$distro_preflight"
    fi
    
    # 2. Dependencies
    # NOTE: a missing dependency folder must NOT abort the rest of setup.
    # Profiles like ML4W's repo don't ship setup/dependencies, and returning
    # early here silently skipped step 4 (the user post.sh hook) — which is
    # where Hyprland 0.56 compat fixes live. Warn and continue instead.
    if [ ! -d "$dep_dir" ]; then 
        warn "Dependency folder not found at: $dep_dir — skipping dependency install (post-install hooks will still run)."
    else
        FAILED_PACKAGES=()
        [ -f "$dep_dir/packages" ] && process_package_file "$dep_dir/packages"
        local distro_pkgs="$dep_dir/packages-$distro"
        [ -f "$distro_pkgs" ] && process_package_file "$distro_pkgs"
        if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
            warn "${#FAILED_PACKAGES[@]} package(s) could not be installed: ${FAILED_PACKAGES[*]}"
            warn "See the logfile for details: $LOG_FILE"
        fi
    fi

    # 3. Repo Post-installation (general first, then distro-specific)
    local postflight="$repo_path/setup/post.sh"
    if [ -f "$postflight" ]; then
        info "Running post-installation script $postflight..."
        source "$postflight"
    fi
    local distro_postflight="$repo_path/setup/post-$distro.sh"
    if [ -f "$distro_postflight" ]; then 
        info "Running post-installation script $distro_postflight for $distro..."
        source "$distro_postflight"
    fi

    # 4. User-specific Post-installation
    local user_post="$user_config_dir/post.sh"
    if [ -f "$user_post" ]; then
        info "Running user-specific post-installation script for $profile_id..."
        source "$user_post"
    fi
}

# --- Run Migration Script for file modifications after creating the symbolic links ---
run_migration() {
    local repo_path=$1
    local profile_id=$2
    local migration="$repo_path/setup/migration.sh"
    if [ -f $migration ]; then
        info "Running migration script $migration for $profile_id..."
        source "$migration"
    fi
}

# --- Check dotfiles installer dependencies ---
check_dependencies() {
    info "Checking system dependencies..."
    local failed=false
    check_and_install "make" "make" || failed=true
    check_and_install "git" "git" || failed=true
    check_and_install "curl" "curl" || failed=true
    check_and_install "jq" "jq" || failed=true
    check_and_install "gum" "gum" || failed=true
    if [ "$failed" = true ]; then
        error "Required tools for the installer are missing. Exiting."
        exit 1
    fi
}

# --- Active Profile Tracker ---
set_active_profile() {
    local id=$1
    local active_file="$INSTALLER_CONFIG/active.json"

    # Write the JSON object to the file
    echo "{\"active\":\"$id\"}" > "$active_file"
    
    info "Profile '$id' marked as active in $active_file"
}

# --- Read remote or local dotinst file and show installation profile ---
read_dotinst() {
    local source=$1; local target_base_dir=$2; local test_mode=$3
    local content=$(get_json_content "$source")
    
    if [ $? -ne 0 ] || [ -z "$content" ]; then 
        error "Failed to read configuration from: $source"
        return 1 
    fi

    local name=$(echo "$content" | jq -r '.name // "Unknown Profile"')
    local id=$(echo "$content" | jq -r '.id // "N/A"')
    local author=$(echo "$content" | jq -r '.author // "N/A"')
    local homepage=$(echo "$content" | jq -r '.homepage // "N/A"')
    local description=$(echo "$content" | jq -r '.description // "No description provided."')
    local version=$(echo "$content" | jq -r '.version // "N/A"')
    local tag=$(echo "$content" | jq -r '.tag // empty')
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
    # Detection line for User Post Script
    if [ -f "$user_post" ]; then
        echo -e "User Script: ${GREEN}Detected${NC}" >&2
    else
        echo -e "User Script: None" >&2
    fi
    echo -e "Description: $description" >&2
    echo -e "${GREEN}--------------------------------------------------${NC}" >&2

    if [ "${ML4W_YES:-0}" != "1" ] && ! gum confirm "Do you want to proceed with the installation?"; then info "Installation cancelled by user."; exit 0; fi

    local working_dir=$(mktemp -d -t ml4w-dots-XXXXXX)
    if [ -d "$git_url" ]; then
        info "Local repository detected. Copying source..."
        cp -a "$git_url/." "$working_dir/"
    else
        info "Remote repository detected. Cloning source..."
        local clone_cmd="git clone --depth=1"
        [ -n "$tag" ] && [ "$tag" != "null" ] && clone_cmd="git clone --depth=1 --branch $tag"
        if ! $clone_cmd "$git_url" "$working_dir"; then 
            error "Failed to clone repository."; rm -rf "$working_dir"; return 1
        fi
    fi
    printf "%s %s %s" "$working_dir" "$id" "$subfolder"
}
