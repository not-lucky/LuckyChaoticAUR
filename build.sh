#!/bin/bash
set -e

#############################################
# Configuration (can be overridden via environment variables)
#############################################

# Repository configuration
REPO_NAME="${REPO_NAME:-luckyrepo}"
WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"
REPO_DIR="${REPO_DIR:-$WORKSPACE_DIR/repo}"

# Build configuration
MAX_PARALLEL="${MAX_PARALLEL:-4}"
MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}"

# Build user configuration
BUILD_USER="${BUILD_USER:-builduser}"
BUILD_GROUP="${BUILD_GROUP:-users}"
BUILD_SHELL="${BUILD_SHELL:-/bin/bash}"
BUILD_HOME="${BUILD_HOME:-/home/$BUILD_USER}"

# Lock file for preventing pacman conflicts
LOCK_FILE="${LOCK_FILE:-/run/pacman-aur/lock}"

# Git/AUR configuration
AUR_URL="${AUR_URL:-https://aur.archlinux.org}"
GIT_CLONE_RETRIES="${GIT_CLONE_RETRIES:-10}"
GIT_CLONE_RETRY_SLEEP="${GIT_CLONE_RETRY_SLEEP:-3}"
GIT_SSL_BACKEND="${GIT_SSL_BACKEND:-openssl}"

# Package list file
PACKAGES_FILE="${PACKAGES_FILE:-$WORKSPACE_DIR/packages.txt}"

# Base packages to install
BASE_PACKAGES="${BASE_PACKAGES:-base-devel git sudo util-linux pacman-contrib ca-certificates}"

# Additional dependencies (space-separated list)
# Common GUI dependencies for packages like browsers, electron apps, etc.
EXTRA_DEPS="${EXTRA_DEPS:-alsa-lib cairo gtk3 libcups libsoup3 libx11 libxcb \
    libxcomposite libxdamage libxext libxfixes libxkbcommon libxkbfile libxrandr \
    mesa nspr nss pango webkit2gtk-4.1}"

# Pacman options
PACMAN_NOCONFIRM="${PACMAN_NOCONFIRM:---noconfirm}"
PACMAN_NEEDED="${PACMAN_NEEDED:---needed}"

#############################################
# Helper functions
#############################################

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

#############################################
# Main script
#############################################

log_info "Initializing pacman ..."
pacman-key --init
pacman -Sy $PACMAN_NOCONFIRM $BASE_PACKAGES

if [ -n "$EXTRA_DEPS" ]; then
    log_info "Installing extra dependencies..."
    pacman -S $PACMAN_NOCONFIRM $PACMAN_NEEDED $EXTRA_DEPS
fi

log_info "Creating build user..."
useradd -m -g "$BUILD_GROUP" -s "$BUILD_SHELL" "$BUILD_USER" || true
echo "$BUILD_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$BUILD_USER"

# Configure git for better SSL handling
log_info "Configuring git..."
git config --global http.sslBackend "$GIT_SSL_BACKEND"
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999

# Create lock file directory and file that builduser can access
log_info "Setting up lock file..."
mkdir -p "$(dirname "$LOCK_FILE")"
touch "$LOCK_FILE"
chown "$BUILD_USER:$BUILD_GROUP" "$LOCK_FILE"

mkdir -p "$REPO_DIR"
chown -R "$BUILD_USER:$BUILD_GROUP" "$REPO_DIR"

# Export variables for subshells
export REPO_DIR
export WORKSPACE_DIR
export MAKEFLAGS

build_package() {
    local pkg=$1
    echo "=========================================="
    echo " STARTING BUILD: $pkg"
    echo "=========================================="

    # Run as build user
    sudo -u "$BUILD_USER" bash -c "
        set -e
        cd \"$BUILD_HOME\"
        rm -rf \"\${pkg}\"

        # Clone with retry logic for network issues
        for i in \$(seq 1 $GIT_CLONE_RETRIES); do
            if git clone --depth 1 $AUR_URL/\${pkg}.git; then
                break
            elif [ \$i -eq $GIT_CLONE_RETRIES ]; then
                echo \"Failed to clone \${pkg} after $GIT_CLONE_RETRIES attempts\"
                exit 1
            else
                echo \"Clone attempt \$i failed, retrying...\"
                sleep $GIT_CLONE_RETRY_SLEEP
            fi
        done

        cd \${pkg}

        # Build the package (makepkg -s will use sudo for pacman to install deps)
        echo \"[\${pkg}] Building package...\"
        flock \"$LOCK_FILE\" bash -c 'MAKEFLAGS=\"\$MAKEFLAGS\" makepkg -s --noconfirm --nocolor'

        # Move output to repo
        cp *.pkg.tar.zst \"$REPO_DIR/\" || true
    "
    echo "=========================================="
    echo " FINISHED BUILD: $pkg"
    echo "=========================================="
}

export -f build_package
export BUILD_USER
export BUILD_HOME
export AUR_URL
export GIT_CLONE_RETRIES
export GIT_CLONE_RETRY_SLEEP
export LOCK_FILE

# Check if packages file exists
if [ ! -f "$PACKAGES_FILE" ]; then
    log_error "Packages file not found: $PACKAGES_FILE"
    exit 1
fi

# Filter packages file to remove comments and empty lines
grep -v '^#' "$PACKAGES_FILE" | grep -v '^$' > "$WORKSPACE_DIR/packages_filtered.txt"

log_info "Starting parallel builds (max $MAX_PARALLEL concurrent)..."
cat "$WORKSPACE_DIR/packages_filtered.txt" | xargs -I {} -P "$MAX_PARALLEL" bash -c 'build_package "{}"'

echo "=========================================="
echo " CREATING PACMAN REPOSITORY"
echo "=========================================="

cd "$REPO_DIR"
repo-add -s -n -R "${REPO_NAME}.db.tar.gz" *.pkg.tar.zst

# Remove the symlinks and rename the databases so they can be uploaded properly
rm -f "${REPO_NAME}.db" "${REPO_NAME}.files"
mv "${REPO_NAME}.db.tar.gz" "${REPO_NAME}.db"
mv "${REPO_NAME}.files.tar.gz" "${REPO_NAME}.files"

echo "Repository contents:"
ls -lh "$REPO_DIR"
