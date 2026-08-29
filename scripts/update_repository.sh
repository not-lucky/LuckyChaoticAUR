#!/bin/bash
set -eo pipefail

REPO="$1"
BRANCH="$2"
TOKEN="$3"
ARCH="x86_64"
DB_NAME="lucky-chaotic"

if [ -z "$REPO" ] || [ -z "$BRANCH" ] || [ -z "$TOKEN" ]; then
  echo "Usage: $0 <owner/repo> <branch> <token>"
  exit 1
fi

WORKSPACE_DIR=$(pwd)
REPO_DIR="${WORKSPACE_DIR}/repo-dir"
NEW_PACKAGES_DIR="/tmp/new-packages"

# Setup GitHub CLI Token
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

# Download existing repository assets from the release if they exist
echo "Downloading existing repository assets..."
mkdir -p "${REPO_DIR}/${ARCH}"
gh release download "$BRANCH" --repo "$REPO" --dir "${REPO_DIR}/${ARCH}" --pattern "*" || echo "No existing release found."

# Process each new package file
echo "Processing new packages..."
if [ -d "$NEW_PACKAGES_DIR" ] && [ "$(ls -A "$NEW_PACKAGES_DIR" 2>/dev/null)" ]; then
  cd "$NEW_PACKAGES_DIR"
  for pkgpath in *.pkg.tar.zst; do
    [ -f "$pkgpath" ] || continue
    pkgfile=$(basename "$pkgpath")
    echo "New package built: $pkgfile"
    
    # Arch package name parsing: split from the right by '-'
    # format: name-ver-rel-arch.pkg.tar.zst
    base="${pkgfile%.pkg.tar.zst}"
    base="${base%-*}"  # Strip arch
    base="${base%-*}"  # Strip rel
    pkgname="${base%-*}"  # Strip ver
    
    echo "Extracted package name: $pkgname"
    
    # Remove old package files of the same package name from the repo-dir
    echo "Removing old files for $pkgname in repo-dir..."
    for existing_path in "${REPO_DIR}/${ARCH}"/*.pkg.tar.zst; do
      [ -f "$existing_path" ] || continue
      existing_file=$(basename "$existing_path")
      
      ex_base="${existing_file%.pkg.tar.zst}"
      ex_base="${ex_base%-*}"
      ex_base="${ex_base%-*}"
      ex_pkgname="${ex_base%-*}"
      
      if [ "$ex_pkgname" = "$pkgname" ]; then
        echo "  Deleting old local file: $existing_file"
        rm -f "$existing_path"
        echo "  Deleting old release asset: $existing_file"
        gh release delete-asset "$BRANCH" "$existing_file" --repo "$REPO" --yes 2>/dev/null || true
      fi
    done
    
    # Copy the new package file
    cp "$pkgpath" "${REPO_DIR}/${ARCH}/"
  done
else
  echo "No new packages found in $NEW_PACKAGES_DIR."
fi

# Go to repo-dir/arch
cd "${REPO_DIR}/${ARCH}"

# Run repo-add to update the database
# We pass all *.pkg.tar.zst files in the directory to repo-add to regenerate/update the database
echo "Updating pacman database..."
if [ "$(ls -A *.pkg.tar.zst 2>/dev/null)" ]; then
  # Initialize keyring just in case
  pacman-key --init || true
  pacman-key --populate archlinux || true
  
  repo-add -R "${DB_NAME}.db.tar.zst" *.pkg.tar.zst
  
  # Replace symlinks with actual copies to support raw download hosting
  echo "Converting symlinks to real files..."
  for link in "${DB_NAME}.db" "${DB_NAME}.files"; do
    if [ -L "$link" ] || [ -f "$link" ]; then
      # If it's a symlink, resolve its target and replace it
      if [ -L "$link" ]; then
        target=$(readlink "$link")
        rm "$link"
        cp "$target" "$link"
      fi
    fi
  done
else
  echo "No package files found to build repository database."
fi

# Publish / Upload to GitHub Release
echo "Publishing to GitHub Release $BRANCH..."

# Check if release exists; if not, create it
if ! gh release view "$BRANCH" --repo "$REPO" >/dev/null 2>&1; then
  echo "Creating release $BRANCH..."
  gh release create "$BRANCH" \
    --repo "$REPO" \
    --title "Pacman Repository" \
    --notes "Automated repository update: $(date -u)"
fi

# Upload all files, overwriting existing assets of the same name
echo "Uploading assets to release $BRANCH..."
gh release upload "$BRANCH" * --repo "$REPO" --clobber

echo "Repository successfully updated on GitHub Releases."
