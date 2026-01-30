# update-repo.sh - Generate pacman repository database using repo-add
#
# Usage: ./update-repo.sh <repo-name> [package-dir]
#
# This script:
#   1. Runs repo-add to create/update the package database
#   2. Creates symlinks for .db and .files
#
# Exit codes:
#   0 - Success
#   1 - Failed to generate database
#   2 - No packages found

set -euo pipefail

REPO_NAME="${1:-}"
PACKAGE_DIR="${2:-./repo/x86_64}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Restore filename from artifact upload sanitization (replace _EPOCH_ with colons)
restore_filename() {
    echo "${1//_EPOCH_/:}"
}

usage() {
    echo "Usage: $0 <repo-name> [package-dir]"
    echo ""
    echo "Generate pacman repository database"
    echo ""
    echo "Arguments:"
    echo "  repo-name    Name of the repository (e.g., 'myrepo')"
    echo "  package-dir  Directory containing .pkg.tar.zst files (default: ./repo/x86_64)"
    echo ""
    exit 1
}

# Check if repository name provided
if [[ -z "$REPO_NAME" ]]; then
    log_error "Repository name is required"
    usage
fi

# Update repository database
update_repo() {
    local repo="$1"
    local pkg_dir="$2"
    local db_file="${pkg_dir}/${repo}.db.tar.gz"
    local repo_add_args=("--remove")

    # Check if package directory exists
    if [[ ! -d "$pkg_dir" ]]; then
        log_error "Package directory not found: $pkg_dir"
        return 1
    fi

    # Check for package files
    local pkg_count
    pkg_count=$(find "$pkg_dir" -maxdepth 1 -name "*.pkg.tar.zst" 2>/dev/null | wc -l)

    if [[ "$pkg_count" -eq 0 ]]; then
        log_warn "No package files found in $pkg_dir"
        log_info "Creating empty repository database..."
    else
        log_info "Found $pkg_count package(s) in $pkg_dir"
    fi

    log_step "Generating repository database: $db_file"

    # Change to package directory
    pushd "$pkg_dir" > /dev/null

    # Restore epoch colons in filenames (sanitized for artifact upload)
    for pkg in *_EPOCH_*.pkg.tar.zst; do
        [[ -f "$pkg" ]] || continue
        local restored
        restored=$(restore_filename "$pkg")
        log_info "Restoring filename: $pkg -> $restored"
        mv "$pkg" "$restored"
    done

    # Remove old database files
    rm -f "${repo}.db" "${repo}.db.tar.gz"
    rm -f "${repo}.files" "${repo}.files.tar.gz"

    # Get all package files
    local packages
    packages=$(find . -maxdepth 1 -name "*.pkg.tar.zst" -printf "%f\n" 2>/dev/null | sort)

    if [[ -n "$packages" ]]; then
        # Run repo-add for each package
        for pkg in $packages; do
            log_info "Adding package: $pkg"
            if ! repo-add "${repo_add_args[@]}" "${repo}.db.tar.gz" "$pkg"; then
                log_error "Failed to add package: $pkg"
                popd > /dev/null
                return 1
            fi
        done
    else
        # Create empty database
        log_info "Creating empty database..."
        if ! repo-add "${repo_add_args[@]}" "${repo}.db.tar.gz"; then
            log_error "Failed to create empty database"
            popd > /dev/null
            return 1
        fi
    fi

    # Create symlinks (repo-add should create these, but ensure they exist)
    if [[ -f "${repo}.db.tar.gz" ]] && [[ ! -L "${repo}.db" ]]; then
        ln -sf "${repo}.db.tar.gz" "${repo}.db"
    fi
    if [[ -f "${repo}.files.tar.gz" ]] && [[ ! -L "${repo}.files" ]]; then
        ln -sf "${repo}.files.tar.gz" "${repo}.files"
    fi

    popd > /dev/null

    log_info "Repository database generated successfully"
    return 0
}

# List repository contents
list_repo() {
    local pkg_dir="$1"

    log_step "Repository contents:"
    echo ""
    echo "Database files:"
    ls -la "$pkg_dir"/*.db* 2>/dev/null || echo "  (none)"
    echo ""
    echo "Files database:"
    ls -la "$pkg_dir"/*.files* 2>/dev/null || echo "  (none)"
    echo ""
    echo "Packages:"
    ls -la "$pkg_dir"/*.pkg.tar.zst 2>/dev/null || echo "  (none)"
    echo ""
}

# Main execution
main() {
    log_step "Updating repository: $REPO_NAME"
    log_info "Package directory: $PACKAGE_DIR"

    if ! update_repo "$REPO_NAME" "$PACKAGE_DIR"; then
        log_error "Failed to update repository"
        exit 1
    fi

    list_repo "$PACKAGE_DIR"

    log_info "Repository update completed successfully"
}

main

# List repository contents
list_repo() {
    local pkg_dir="$1"

    log_step "Repository contents:"
    echo ""
    echo "Database files:"
    ls -la "$pkg_dir"/*.db* 2>/dev/null || echo "  (none)"
    echo ""
    echo "Files database:"
    ls -la "$pkg_dir"/*.files* 2>/dev/null || echo "  (none)"
    echo ""
    echo "Packages:"
    ls -la "$pkg_dir"/*.pkg.tar.zst 2>/dev/null || echo "  (none)"
    echo ""
}

# Main execution
main() {
    log_step "Updating repository: $REPO_NAME"
    log_info "Package directory: $PACKAGE_DIR"

    if ! update_repo "$REPO_NAME" "$PACKAGE_DIR"; then
        log_error "Failed to update repository"
        exit 1
    fi

    list_repo "$PACKAGE_DIR"

    log_info "Repository update completed successfully"
}

main
