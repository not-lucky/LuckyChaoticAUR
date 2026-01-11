#!/bin/bash
# fetch-pkgbuild.sh - Fetch PKGBUILD and related files from AUR
#
# Usage: ./fetch-pkgbuild.sh <package-name>
#
# Exit codes:
#   0 - Success
#   1 - Package not found
#   2 - Network error
#   3 - Git clone failed

set -euo pipefail

PACKAGE="${1:-}"
AUR_BASE_URL="https://aur.archlinux.org"
OUTPUT_DIR="${2:-./aur}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    echo "Usage: $0 <package-name> [output-dir]"
    echo ""
    echo "Fetch PKGBUILD and related files from AUR"
    echo ""
    echo "Arguments:"
    echo "  package-name  Name of the AUR package to fetch"
    echo "  output-dir    Directory to store fetched files (default: ./aur)"
    exit 1
}

# Check if package name provided
if [[ -z "$PACKAGE" ]]; then
    log_error "Package name is required"
    usage
fi

# Check if package exists in AUR using RPC API
check_package_exists() {
    local pkg="$1"
    local response

    log_info "Checking if package '$pkg' exists in AUR..."

    response=$(curl -sf "${AUR_BASE_URL}/rpc/v5/info?arg[]=${pkg}" 2>/dev/null) || {
        log_error "Network error while checking package"
        return 2
    }

    local resultcount
    resultcount=$(echo "$response" | jq -r '.resultcount // 0')

    if [[ "$resultcount" -eq 0 ]]; then
        log_error "Package '$pkg' not found in AUR"
        return 1
    fi

    log_info "Package '$pkg' found in AUR"
    return 0
}

# Clone the package from AUR git repository
clone_package() {
    local pkg="$1"
    local dest="$2"

    local git_url="${AUR_BASE_URL}/${pkg}.git"

    log_info "Cloning package from ${git_url}..."

    # Remove existing directory if it exists
    if [[ -d "$dest" ]]; then
        log_warn "Removing existing directory: $dest"
        rm -rf "$dest"
    fi

    # Clone the repository
    if ! git clone --depth 1 "$git_url" "$dest" 2>/dev/null; then
        log_error "Failed to clone repository for '$pkg'"
        return 3
    fi

    # Verify PKGBUILD exists
    if [[ ! -f "${dest}/PKGBUILD" ]]; then
        log_error "PKGBUILD not found in cloned repository"
        return 1
    fi

    log_info "Successfully fetched PKGBUILD for '$pkg'"
    return 0
}

# Get package info from AUR API
get_package_info() {
    local pkg="$1"
    local response

    response=$(curl -sf "${AUR_BASE_URL}/rpc/v5/info?arg[]=${pkg}" 2>/dev/null) || return 2

    echo "$response" | jq -r '.results[0]'
}

# Main execution
main() {
    local package_dir="${OUTPUT_DIR}/${PACKAGE}"

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Check if package exists
    if ! check_package_exists "$PACKAGE"; then
        exit 1
    fi

    # Clone the package
    if ! clone_package "$PACKAGE" "$package_dir"; then
        exit 3
    fi

    # Save package info to JSON file
    log_info "Saving package metadata..."
    if get_package_info "$PACKAGE" > "${package_dir}/aur-info.json"; then
        log_info "Package metadata saved to ${package_dir}/aur-info.json"
    else
        log_warn "Could not save package metadata"
    fi

    # List fetched files
    log_info "Fetched files:"
    ls -la "$package_dir"

    log_info "Successfully fetched '$PACKAGE' to $package_dir"
}

main
