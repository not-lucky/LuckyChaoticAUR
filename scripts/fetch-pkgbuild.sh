#!/bin/bash
# fetch-pkgbuild.sh - Fetch PKGBUILD and related files from AUR
#
# Usage: ./fetch-pkgbuild.sh <package-name> [output-dir] [--force] [--versions-file <path>]
#
# Exit codes:
#   0 - Success
#   1 - Package not found in AUR
#   2 - Network error
#   3 - Git clone failed
#   4 - Package exists in official repos (skipped)
#   5 - Package version unchanged since last build (skipped)

set -euo pipefail

PACKAGE=""
AUR_BASE_URL="https://aur.archlinux.org"
OUTPUT_DIR="./aur"
FORCE_BUILD=false
VERSIONS_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE_BUILD=true
            shift
            ;;
        --versions-file)
            VERSIONS_FILE="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$PACKAGE" ]]; then
                PACKAGE="$1"
            else
                OUTPUT_DIR="$1"
            fi
            shift
            ;;
    esac
done

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
    echo "Usage: $0 <package-name> [output-dir] [--force] [--versions-file <path>]"
    echo ""
    echo "Fetch PKGBUILD and related files from AUR"
    echo ""
    echo "Arguments:"
    echo "  package-name         Name of the AUR package to fetch"
    echo "  output-dir           Directory to store fetched files (default: ./aur)"
    echo ""
    echo "Options:"
    echo "  --force              Force fetch even if version unchanged"
    echo "  --versions-file      Path to versions.json for version comparison"
    exit 1
}

# Check if package name provided
if [[ -z "$PACKAGE" ]]; then
    log_error "Package name is required"
    usage
fi

# Check if package exists in official Arch repos
check_official_repos() {
    local pkg="$1"
    local response

    log_info "Checking if package '$pkg' exists in official repos..."

    response=$(curl -sf "https://archlinux.org/packages/search/json/?name=${pkg}" 2>/dev/null) || {
        log_warn "Could not check official repos (network error)"
        return 1
    }

    local resultcount
    resultcount=$(echo "$response" | jq -r '.results | length')

    if [[ "$resultcount" -gt 0 ]]; then
        local repo
        repo=$(echo "$response" | jq -r '.results[0].repo')
        log_warn "Package '$pkg' found in official repo '$repo' - skipping AUR build"
        return 0
    fi

    return 1
}

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

# Get package version from AUR API response
get_aur_version() {
    local pkg="$1"
    local response

    response=$(curl -sf "${AUR_BASE_URL}/rpc/v5/info?arg[]=${pkg}" 2>/dev/null) || return 2

    echo "$response" | jq -r '.results[0].Version // empty'
}

# Get cached version from versions.json
get_cached_version() {
    local pkg="$1"
    local versions_file="$2"

    if [[ -z "$versions_file" ]] || [[ ! -f "$versions_file" ]]; then
        echo ""
        return
    fi

    jq -r --arg pkg "$pkg" '.[$pkg] // empty' "$versions_file" 2>/dev/null || echo ""
}

# Check if version has changed
check_version_changed() {
    local pkg="$1"
    local aur_version="$2"
    local cached_version="$3"

    if [[ -z "$cached_version" ]]; then
        log_info "No cached version for '$pkg' - will build"
        return 0
    fi

    if [[ "$aur_version" == "$cached_version" ]]; then
        log_info "Version unchanged for '$pkg': $aur_version"
        return 1
    fi

    log_info "Version changed for '$pkg': $cached_version -> $aur_version"
    return 0
}

# Main execution
main() {
    local package_dir="${OUTPUT_DIR}/${PACKAGE}"

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Check if package exists in official repos first
    if check_official_repos "$PACKAGE"; then
        log_info "Skipping '$PACKAGE' - available in official repositories"
        exit 4
    fi

    # Check if package exists in AUR
    if ! check_package_exists "$PACKAGE"; then
        exit 1
    fi

    # Check version if not forcing and versions file provided
    if [[ "$FORCE_BUILD" != "true" ]] && [[ -n "$VERSIONS_FILE" ]]; then
        local aur_version
        aur_version=$(get_aur_version "$PACKAGE")
        
        if [[ -n "$aur_version" ]]; then
            local cached_version
            cached_version=$(get_cached_version "$PACKAGE" "$VERSIONS_FILE")
            
            if ! check_version_changed "$PACKAGE" "$aur_version" "$cached_version"; then
                log_info "Skipping '$PACKAGE' - version unchanged since last build"
                exit 5
            fi
        fi
    elif [[ "$FORCE_BUILD" == "true" ]]; then
        log_info "Force build requested - skipping version check"
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
