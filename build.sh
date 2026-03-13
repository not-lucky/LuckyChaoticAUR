#!/bin/bash
set -e

REPO_NAME="luckyrepo"
WORKSPACE_DIR=$(pwd)
REPO_DIR="$WORKSPACE_DIR/repo"

echo "Initializing pacman ..."
pacman-key --init
pacman -Sy --noconfirm base-devel git sudo

echo "Creating build user..."
useradd -m -g users -s /bin/bash builduser || true
echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser

mkdir -p "$REPO_DIR"
chown -R builduser:users "$REPO_DIR"

while IFS= read -r pkg; do
    # Skip empty lines and comments
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue

    echo "=========================================="
    echo " BUILDING: $pkg"
    echo "=========================================="

    sudo -u builduser bash -c "
        cd /home/builduser
        git clone https://aur.archlinux.org/${pkg}.git
        cd ${pkg}
        MAKEFLAGS=\"-j\$(nproc)\" makepkg -s --noconfirm
        cp *.pkg.tar.zst \"$REPO_DIR/\"
    "
done < "$WORKSPACE_DIR/packages.txt"

echo "=========================================="
echo " CREATING PACMAN REPOSITORY"
echo "=========================================="

cd "$REPO_DIR"
repo-add -s -n -R ${REPO_NAME}.db.tar.gz *.pkg.tar.zst

# Remove the symlinks and rename the databases so they can be uploaded properly
# as GitHub Releases does not support symlinks.
rm -f ${REPO_NAME}.db ${REPO_NAME}.files
mv ${REPO_NAME}.db.tar.gz ${REPO_NAME}.db
mv ${REPO_NAME}.files.tar.gz ${REPO_NAME}.files

echo "Repository contents:"
ls -lh "$REPO_DIR"
