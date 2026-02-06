#!/bin/bash

################################################################################
# sync_ec2.sh - Sync files between local machine and EC2 instance
################################################################################
#
# Usage:
#   ./sync_ec2.sh [OPTIONS]
#
# Options:
#   -i IP_ADDRESS    EC2 IP address (required if EC2_IP not set in script)
#   -d DIRECTION     "download" (EC2→local) or "upload" (local→EC2) [default: download]
#   -r REMOTE_PATH   Remote path on EC2 [default: Copula_Sensitivity_Analyses/STEP_1_Family_Selection/results/]
#   -l LOCAL_PATH    Local path [default: .]
#   -k KEY_PATH      SSH key path [default: ~/.ec2/SGP.pem]
#   -n               Dry run (show what would be transferred)
#   -h               Show this help message
#
# Examples:
#   # Download results (from results directory)
#   ./sync_ec2.sh -i 54.81.74.223
#
#   # Dry run first
#   ./sync_ec2.sh -i 54.81.74.223 -n
#
#   # Upload code changes
#   ./sync_ec2.sh -i 54.81.74.223 -d upload -r Copula_Sensitivity_Analyses/functions/ -l ../functions/
#
#   # Sync entire project
#   ./sync_ec2.sh -i 54.81.74.223 -r Copula_Sensitivity_Analyses/ -l ..
#
################################################################################

# Default configuration (edit these as needed)
EC2_IP=""                    # Set default IP here, or pass with -i flag
EC2_USER="ec2-user"
KEY_PATH="$HOME/.ec2/SGP.pem"
DIRECTION="download"
REMOTE_PATH="Copula_Sensitivity_Analyses/STEP_1_Family_Selection/results/"
LOCAL_PATH="."
DRY_RUN=false

# Source config file if it exists (recommended way to set EC2_IP)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/ec2_config.sh" ]; then
    source "$SCRIPT_DIR/ec2_config.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Functions
################################################################################

show_help() {
    cat << EOF
$(head -n 30 "$0" | tail -n +3)
EOF
    exit 0
}

error_exit() {
    echo -e "${RED}❌ Error: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

################################################################################
# Parse command line arguments
################################################################################

while getopts "i:d:r:l:k:nh" opt; do
    case $opt in
        i) EC2_IP="$OPTARG" ;;
        d) DIRECTION="$OPTARG" ;;
        r) REMOTE_PATH="$OPTARG" ;;
        l) LOCAL_PATH="$OPTARG" ;;
        k) KEY_PATH="$OPTARG" ;;
        n) DRY_RUN=true ;;
        h) show_help ;;
        \?) error_exit "Invalid option: -$OPTARG" ;;
    esac
done

################################################################################
# Validate inputs
################################################################################

# Check if EC2_IP is set
if [ -z "$EC2_IP" ]; then
    error_exit "EC2 IP address required. Use -i flag or set EC2_IP in script."
fi

# Validate direction
if [ "$DIRECTION" != "download" ] && [ "$DIRECTION" != "upload" ]; then
    error_exit "Direction must be 'download' or 'upload', got: $DIRECTION"
fi

# Check if rsync is available
if ! command -v rsync &> /dev/null; then
    error_exit "rsync not found. Install with: brew install rsync (macOS) or apt-get install rsync (Linux)"
fi

# Check if SSH key exists
if [ ! -f "$KEY_PATH" ]; then
    error_exit "SSH key not found at: $KEY_PATH"
fi

# Expand paths
KEY_PATH=$(eval echo "$KEY_PATH")
LOCAL_PATH=$(eval echo "$LOCAL_PATH")

################################################################################
# Build rsync command
################################################################################

# Base flags
# -W (whole-file): Prevents rsync from hanging on large binary files
# --timeout=60: Kill stalled transfers after 60 seconds
RSYNC_FLAGS="-avzW --progress --stats --timeout=60"

# Add dry run flag if requested
if [ "$DRY_RUN" = true ]; then
    RSYNC_FLAGS="$RSYNC_FLAGS -n"
    warning "DRY RUN MODE - No files will be transferred"
    echo ""
fi

# Build source and destination based on direction
REMOTE_FULL="${EC2_USER}@${EC2_IP}:/home/${EC2_USER}/${REMOTE_PATH}"

if [ "$DIRECTION" = "download" ]; then
    SOURCE="$REMOTE_FULL"
    DEST="$LOCAL_PATH"
    ARROW="⬇️  EC2 → Local"
else
    SOURCE="$LOCAL_PATH"
    DEST="$REMOTE_FULL"
    ARROW="⬆️  Local → EC2"
fi

################################################################################
# Display sync information
################################################################################

echo "================================================================================"
echo -e "${BLUE}$ARROW SYNC${NC}"
echo "================================================================================"
echo "Source:    $SOURCE"
echo "Dest:      $DEST"
echo "EC2 IP:    $EC2_IP"
echo "SSH Key:   $KEY_PATH"
if [ "$DRY_RUN" = true ]; then
    echo "Mode:      DRY RUN (no actual transfer)"
fi
echo "================================================================================"
echo ""

################################################################################
# Execute rsync
################################################################################

# Run rsync with SSH keepalive to prevent connection timeouts
rsync $RSYNC_FLAGS -e "ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -i $KEY_PATH" "$SOURCE" "$DEST"

# Check exit status
if [ $? -eq 0 ]; then
    echo ""
    success "Sync completed successfully!"
else
    echo ""
    error_exit "Sync failed with exit code: $?"
fi
