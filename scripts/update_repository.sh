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

# Setup git credentials
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
# Mark workspace as safe
git config --global --add safe.directory "$WORKSPACE_DIR"

repo_url="https://x-access-token:${TOKEN}@github.com/${REPO}.git"

# Clone the repository branch if it exists, otherwise initialize it
echo "Cloning or initializing the $BRANCH branch..."
git clone --branch "$BRANCH" "$repo_url" "$REPO_DIR" || {
  echo "Branch $BRANCH does not exist. Creating a new one..."
  mkdir -p "$REPO_DIR"
  cd "$REPO_DIR"
  git init
  git checkout -b "$BRANCH"
  git remote add origin "$repo_url"
  cd "$WORKSPACE_DIR"
}

# Mark repo-dir as safe
git config --global --add safe.directory "$REPO_DIR"

mkdir -p "${REPO_DIR}/${ARCH}"

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
        echo "  Deleting old file: $existing_file"
        rm -f "$existing_path"
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
  
  # Replace symlinks with actual copies to support raw github hosting
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

# Go to repo-dir root
cd "$REPO_DIR"

# Commit and force-push as orphan commit to save space
echo "Committing and force-pushing..."
git add -A

# Check if there are any changes to commit
if git diff --cached --quiet; then
  echo "No changes in the repository branch."
  exit 0
fi

# Create an orphan commit to prevent git history bloat
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  git checkout --orphan temp-branch
  git commit -m "Automated build: $(date -u)"
  git branch -M "$BRANCH"
else
  git commit -m "Automated build: $(date -u)"
fi

git push origin "$BRANCH" --force
echo "Repository branch $BRANCH successfully updated."
