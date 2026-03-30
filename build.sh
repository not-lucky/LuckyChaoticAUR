#!/bin/bash
set -e

REPO_NAME="luckyrepo"
WORKSPACE_DIR=$(pwd)
REPO_DIR="$WORKSPACE_DIR/repo"
# Number of parallel package builds (2-4 is usually best for GitHub Runners)
MAX_PARALLEL=4

echo "Initializing pacman ..."
pacman-key --init
pacman -Sy --noconfirm base-devel git sudo util-linux pacman-contrib ca-certificates

# Install common AUR build dependencies that are often needed
pacman -S --noconfirm --needed alsa-lib cairo gtk3 libcups libsoup3 libx11 libxcb \
    libxcomposite libxdamage libxext libxfixes libxkbcommon libxkbfile libxrandr \
    mesa nspr nss pango webkit2gtk-4.1

echo "Creating build user..."
useradd -m -g users -s /bin/bash builduser || true
echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser

# Configure git for better SSL handling
git config --global http.sslBackend openssl
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999

# Create lock file directory and file that builduser can access
mkdir -p /run/pacman-aur
touch /run/pacman-aur/lock
chown builduser:users /run/pacman-aur/lock

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
        set -e
        cd /home/builduser
        rm -rf \"${pkg}\"

        # Clone with retry logic for network issues
        for i in 1 2 3; do
            if git clone --depth 1 https://aur.archlinux.org/${pkg}.git; then
                break
            elif [ \$i -eq 3 ]; then
                echo \"Failed to clone ${pkg} after 3 attempts\"
                exit 1
            else
                echo \"Clone attempt \$i failed, retrying...\"
                sleep 2
            fi
        done

        cd ${pkg}

        # Install dependencies (requires sudo, makepkg -s --nobuild handles this)
        echo \"[$pkg] Installing dependencies...\"
        flock /run/pacman-aur/lock sudo pacman -S --noconfirm --needed \$(makepkg -O)

        # Build the package as builduser (NOT as root)
        echo \"[$pkg] Compiling...\"
        MAKEFLAGS=\"-j\$(nproc)\" makepkg --noconfirm --nocolor

        # Move output to repo
        cp *.pkg.tar.zst \"$REPO_DIR/\" || true
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
