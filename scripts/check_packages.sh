#!/bin/bash
set -eo pipefail

# Inputs
REPO="$1"
BRANCH="$2"
ARCH="x86_64"

if [ -z "$REPO" ] || [ -z "$BRANCH" ]; then
  echo "Usage: $0 <owner/repo> <branch>"
  exit 1
fi

# Setup non-root builder user if it doesn't exist
if ! id -u builder >/dev/null 2>&1; then
  useradd -m builder
  echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# Read packages.txt
packages=()
if [ -f packages.txt ]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip carriage return characters if present
    line=$(echo "$line" | tr -d '\r')
    # Ignore empty lines and comments
    [[ "$line" =~ ^# ]] && continue
    [[ -z "$line" ]] && continue
    packages+=("$line")
  done < packages.txt
else
  echo "Error: packages.txt not found!"
  exit 1
fi

to_build=()

for pkg in "${packages[@]}"; do
  echo "Checking package: $pkg"
  
  # Work in a separate directory for each package
  pkg_dir="/tmp/check-$pkg"
  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir"
  
  if [ -d "$pkg" ]; then
    echo "  Using local package directory: $pkg"
    cp -r "$pkg"/* "$pkg_dir/"
  else
    echo "  Cloning from AUR..."
    git clone "https://aur.archlinux.org/${pkg}.git" "$pkg_dir"
  fi
  
  # Fix ownership for builder
  chown -R builder:builder "$pkg_dir"
  
  # Change to package directory to check version info
  pushd "$pkg_dir" >/dev/null
  
  # Fetch sources and update version (crucial for -git packages)
  # Run as builder without checking dependencies
  echo "  Running makepkg -od to resolve version info..."
  sudo -u builder makepkg -od --noconfirm --nodeps >/dev/null 2>&1 || {
    echo "  Warning: failed to update version for $pkg, proceeding with static version."
  }
  
  # Get expected package files
  pkgfiles=$(sudo -u builder makepkg --packagelist)
  
  pkg_needed=false
  for pkgfile in $pkgfiles; do
    pkgname=$(basename "$pkgfile")
    url="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${ARCH}/${pkgname}"
    
    # Check HTTP status of the package file on raw github
    status_code=$(curl -L -s -o /dev/null -w "%{http_code}" "$url")
    if [ "$status_code" -ne 200 ]; then
      echo "    Package file $pkgname not found (HTTP status: $status_code). Build is needed."
      pkg_needed=true
      break
    else
      echo "    Package file $pkgname already exists."
    fi
  done
  
  if [ "$pkg_needed" = "true" ]; then
    to_build+=("$pkg")
  fi
  
  popd >/dev/null
done

# Output JSON array of packages to build and build status
json_array=$(jq -n -c '$ARGS.positional' --args "${to_build[@]}")
echo "packages_to_build=${json_array}"

if [ ${#to_build[@]} -gt 0 ]; then
  echo "build_needed=true"
else
  echo "build_needed=false"
fi
