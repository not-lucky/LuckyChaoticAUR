#!/bin/bash
# build-package.sh - Build an AUR package using makepkg
#
# Usage: ./build-package.sh <package-name> [build-dir] [output-dir]
#
# Environment variables:
#   GPGKEY           - GPG key ID for signing packages
#   SKIP_PGP_CHECK   - If set, skip PGP signature verification
#   PACKAGER         - Packager identity for built packages
#
# Exit codes:
#   0 - Success
#   1 - Build failed
#   2 - Dependency resolution failed
#   3 - Package directory not found

set -euo pipefail

PACKAGE="${1:-}"
BUILD_DIR="${2:-./aur}"
OUTPUT_DIR="${3:-./repo/x86_64}"

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

# Sanitize filename for artifact upload (replace colons with _EPOCH_)
# GitHub Actions artifacts don't allow colons due to NTFS limitations
sanitize_filename() {
    echo "${1//:/_EPOCH_}"
}

usage() {
    echo "Usage: $0 <package-name> [build-dir] [output-dir]"
    echo ""
    echo "Build an AUR package using makepkg"
    echo ""
    echo "Arguments:"
    echo "  package-name  Name of the package to build"
    echo "  build-dir     Directory containing the fetched package (default: ./aur)"
    echo "  output-dir    Directory for built packages (default: ./repo/x86_64)"
    echo ""
    echo "Environment variables:"
    echo "  GPGKEY         GPG key ID for signing (optional)"
    echo "  SKIP_PGP_CHECK Skip PGP checks (optional)"
    echo "  PACKAGER       Packager identity (optional)"
    exit 1
}

# Check if package name provided
if [[ -z "$PACKAGE" ]]; then
    log_error "Package name is required"
    usage
fi

# Build the package
build_package() {
    local pkg="$1"
    local pkg_dir="${BUILD_DIR}/${pkg}"
    local makepkg_args=("-s" "-c" "-f" "--noconfirm")

    # Check if package directory exists
    if [[ ! -d "$pkg_dir" ]]; then
        log_error "Package directory not found: $pkg_dir"
        log_error "Run fetch-pkgbuild.sh first"
        return 3
    fi

    # Check if PKGBUILD exists
    if [[ ! -f "${pkg_dir}/PKGBUILD" ]]; then
        log_error "PKGBUILD not found in $pkg_dir"
        return 3
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Add skip pgp check if requested
    if [[ -n "${SKIP_PGP_CHECK:-}" ]]; then
        log_warn "Skipping PGP signature verification"
        makepkg_args+=("--skippgpcheck")
    fi

    # Add signing if GPGKEY is set
    if [[ -n "${GPGKEY:-}" ]]; then
        log_info "Package will be signed with key: $GPGKEY"
        makepkg_args+=("--sign")
    fi

    # Set packager if provided
    if [[ -n "${PACKAGER:-}" ]]; then
        export PACKAGER
    fi

    log_step "Building package '$pkg'..."
    log_info "Build directory: $pkg_dir"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "makepkg arguments: ${makepkg_args[*]}"

    # Change to package directory and build
    pushd "$pkg_dir" > /dev/null

    # Run makepkg
    if ! makepkg "${makepkg_args[@]}"; then
        log_error "Build failed for package '$pkg'"
        popd > /dev/null
        return 1
    fi

    popd > /dev/null

    # Move built packages to output directory
    log_step "Moving built packages to $OUTPUT_DIR..."
    local pkg_files
    pkg_files=$(find "$pkg_dir" -maxdepth 1 -name "*.pkg.tar.zst" -o -name "*.pkg.tar.zst.sig" 2>/dev/null)

    if [[ -z "$pkg_files" ]]; then
        log_error "No package files found after build"
        return 1
    fi

    for pkg_file in $pkg_files; do
        if [[ -f "$pkg_file" ]]; then
            local filename
            filename=$(basename "$pkg_file")
            # Replace colons with _EPOCH_ for artifact upload compatibility
            local safe_filename
            safe_filename=$(sanitize_filename "$filename")
            if [[ "$filename" != "$safe_filename" ]]; then
                log_info "Renaming $filename -> $safe_filename (epoch sanitization)"
            fi
            log_info "Moving $safe_filename to $OUTPUT_DIR/"
            mv "$pkg_file" "$OUTPUT_DIR/$safe_filename"
        fi
    done

    log_info "Successfully built package '$pkg'"
    return 0
}

# Main execution
main() {
    log_step "Starting build for package: $PACKAGE"

    if ! build_package "$PACKAGE"; then
        log_error "Build failed"
        exit 1
    fi

    log_info "Build completed successfully"

    # List built packages
    log_info "Built packages in $OUTPUT_DIR:"
    ls -la "$OUTPUT_DIR"/*.pkg.tar.zst* 2>/dev/null || true
}

main
