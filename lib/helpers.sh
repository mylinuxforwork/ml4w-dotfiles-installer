#!/usr/bin/env bash

# --- Helper to identify the Linux distro ---
get_distro_by_bin() {
    if command -v pacman &> /dev/null; then echo "arch";
    elif command -v dnf &> /dev/null; then echo "fedora";
    elif command -v zypper &> /dev/null; then echo "opensuse";
    elif command -v apt &> /dev/null; then echo "ubuntu";
    else echo "unknown"; fi
}

# --- Logging ---
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ml4w-dotfiles-installer/logs"
LOG_KEEP=10

# Create a new logfile for this run and remove all but the newest $LOG_KEEP
init_log() {
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d_%H%M%S).log"
    {
        echo "ML4W Dotfiles Installer $SCRIPT_VERSION"
        echo "Date:      $(date '+%F %T')"
        echo "Distro:    $(get_distro_by_bin)"
        echo "Source:    $INSTALL_URL"
        echo "Test Mode: $TEST_MODE"
        echo
    } > "$LOG_FILE"
    ls -1 "$LOG_DIR"/install-*.log 2> /dev/null | sort -r | tail -n +$((LOG_KEEP + 1)) | xargs -r rm -f
}

# --- Run a command with its output written to the logfile ---
# Usage: run_logged [--title "Spinner text"] command [args...]
# Output is hidden (or shown with --verbose); the exit code is passed through.
run_logged() {
    local title=""
    if [ "$1" = "--title" ]; then title=$2; shift 2; fi
    [ -z "$LOG_FILE" ] && LOG_FILE=/dev/null

    echo "----- $(date '+%F %T') \$ $*" >> "$LOG_FILE"
    local rc
    if [ "$VERBOSE" = true ]; then
        "$@" < /dev/null 2>&1 | tee -a "$LOG_FILE" >&2
        rc=${PIPESTATUS[0]}
    elif [ -n "$title" ] && [ -t 2 ] && command -v gum &> /dev/null; then
        gum spin --spinner dot --title "$title" -- \
            bash -c 'log=$1; shift; "$@" < /dev/null >> "$log" 2>&1' _ "$LOG_FILE" "$@"
        rc=$?
    else
        "$@" < /dev/null >> "$LOG_FILE" 2>&1
        rc=$?
    fi
    echo "----- exit code: $rc" >> "$LOG_FILE"
    return $rc
}

# --- Ask for the sudo password once and keep the session alive ---
# Package installs run with hidden output, so a sudo prompt must not appear
# in the middle of a spinner. The keepalive is stopped in the cleanup trap.
ensure_sudo() {
    [ "$EUID" -eq 0 ] && return 0
    [ -n "$SUDO_KEEPALIVE_PID" ] && return 0
    info "Administrator privileges are required to install packages."
    sudo -v || return 1
    ( while kill -0 "$$" 2> /dev/null; do sudo -n true; sleep 50; done ) 2> /dev/null &
    SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
    [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2> /dev/null
    SUDO_KEEPALIVE_PID=""
}

# --- Helper to install a package disto agnostic ---
install_package() {
    local pkg=$1; local distro=$(get_distro_by_bin)
    ensure_sudo || return 1
    case "$distro" in
        arch) run_logged --title "Installing $pkg..." sudo pacman -S --needed --noconfirm "$pkg" ;;
        fedora) run_logged --title "Installing $pkg..." sudo dnf install -y "$pkg" ;;
        opensuse) run_logged --title "Installing $pkg..." sudo zypper --non-interactive install "$pkg" ;;
        ubuntu)
            if [ "$APT_UPDATED" != true ]; then
                run_logged --title "Updating package lists..." sudo apt-get update && APT_UPDATED=true
            fi
            run_logged --title "Installing $pkg..." sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" ;;
        *) error "Unsupported distro."; return 1 ;;
    esac
}

# --- Helper to check command and install if not available ---
check_and_install() {
    local cmd=$1; local pkg=$2
    if command -v "$cmd" &> /dev/null; then return 0; fi

    warn "✗ $cmd is not installed. Installing now..."
    if install_package "$pkg" && command -v "$cmd" &> /dev/null; then
        info "  ✓ $pkg installed."
    else
        error "  ✗ Failed to install $pkg. See $LOG_FILE"
        return 1
    fi
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
