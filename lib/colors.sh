# --- Colors for UI ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- UI Functions (Redirected to stderr, mirrored to the logfile) ---
log_msg() { [ -n "$LOG_FILE" ] && echo "$(date +%T) $1" >> "$LOG_FILE"; return 0; }
info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; log_msg "[INFO] $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; log_msg "[WARN] $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; log_msg "[ERROR] $1"; }