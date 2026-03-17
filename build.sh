#!/bin/bash
set -e

REPO_NAME="luckyrepo"
WORKSPACE_DIR=$(pwd)
REPO_DIR="$WORKSPACE_DIR/repo"
# Number of parallel package builds (2-4 is usually best for GitHub Runners)
MAX_PARALLEL=4

echo "Initializing pacman ..."
pacman-key --init
pacman -Sy --noconfirm base-devel git sudo util-linux

echo "Creating build user..."
useradd -m -g users -s /bin/bash builduser || true
echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser

mkdir -p "$REPO_DIR"
chown -R builduser:users "$REPO_DIR"

# Export variables and function for xargs
export REPO_DIR
export WORKSPACE_DIR

build_package() {
    local pkg=$1
    echo "=========================================="
    echo " STARTING BUILD: $pkg"
    echo "=========================================="

    # Run as builduser
    sudo -u builduser bash -c "
        cd /home/builduser
        rm -rf \"${pkg}\"
        git clone --depth 1 https://aur.archlinux.org/${pkg}.git
        cd ${pkg}

        # We use a lock for dependency installation to prevent pacman lock conflicts
        echo \"[$pkg] Installing dependencies...\"
        sudo flock /run/pacman-aur.lock makepkg -s --noconfirm --nobuild

        # Build the package
        echo \"[$pkg] Compiling...\"
        MAKEFLAGS=\"-j\$(nproc)\" makepkg --noconfirm --nocolor
        
        # Move output to repo
        cp *.pkg.tar.zst \"$REPO_DIR/\"
    "
    echo "=========================================="
    echo " FINISHED BUILD: $pkg"
    echo "=========================================="
}

export -f build_package

# Filter packages.txt to remove comments and empty lines
grep -v '^#' "$WORKSPACE_DIR/packages.txt" | grep -v '^$' > "$WORKSPACE_DIR/packages_filtered.txt"

# Run parallel builds using xargs
cat "$WORKSPACE_DIR/packages_filtered.txt" | xargs -I {} -P "$MAX_PARALLEL" bash -c 'build_package "{}"'

echo "=========================================="
echo " CREATING PACMAN REPOSITORY"
echo "=========================================="

cd "$REPO_DIR"
repo-add -s -n -R ${REPO_NAME}.db.tar.gz *.pkg.tar.zst

# Remove the symlinks and rename the databases so they can be uploaded properly
rm -f ${REPO_NAME}.db ${REPO_NAME}.files
mv ${REPO_NAME}.db.tar.gz ${REPO_NAME}.db
mv ${REPO_NAME}.files.tar.gz ${REPO_NAME}.files

echo "Repository contents:"
ls -lh "$REPO_DIR"
