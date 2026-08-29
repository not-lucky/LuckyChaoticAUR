#!/bin/bash
set -eo pipefail

# Helper function to print logs to stderr so they don't corrupt GITHUB_OUTPUT
log() {
  echo "$@" >&2
}

# Inputs
REPO="$1"
BRANCH="$2"
ARCH="x86_64"

if [ -z "$REPO" ] || [ -z "$BRANCH" ]; then
  log "Usage: $0 <owner/repo> <branch>"
  exit 1
fi

# Setup non-root builder user if it doesn't exist
if ! id -u builder >/dev/null 2>&1; then
  useradd -m builder
  echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# Helper to resolve local package directory
resolve_pkg_dir() {
  local pkg="$1"
  if [ -d "$pkg" ] && [ -f "$pkg/PKGBUILD" ]; then
    echo "$pkg"
  elif [ -d "packages/$pkg" ] && [ -f "packages/$pkg/PKGBUILD" ]; then
    echo "packages/$pkg"
  elif [ -d "pkgs/$pkg" ] && [ -f "pkgs/$pkg/PKGBUILD" ]; then
    echo "pkgs/$pkg"
  else
    echo ""
  fi
}

# Read packages.txt and auto-discover local packages
packages=()
declare -A seen_packages=()

if [ -f packages.txt ]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip carriage return characters if present
    line=$(echo "$line" | tr -d '\r')
    # Ignore empty lines and comments
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # Strip leading/trailing whitespace if needed, and ignore empty lines
    trimmed_line=$(echo "$line" | xargs)
    [[ -z "$trimmed_line" ]] && continue
    pkg_name=$(basename "$trimmed_line")
    if [[ -z "${seen_packages[$pkg_name]}" ]]; then
      packages+=("$pkg_name")
      seen_packages["$pkg_name"]=1
    fi
  done < packages.txt
fi

# Auto-discover local packages in repo (root subdirectories, packages/*, pkgs/*)
shopt -s nullglob
for dir in */ packages/*/ pkgs/*/; do
  dir="${dir%/}"
  if [ -d "$dir" ] && [ -f "$dir/PKGBUILD" ]; then
    pkg_name=$(basename "$dir")
    if [[ "$pkg_name" != "scripts" && "$pkg_name" != ".github" && -z "${seen_packages[$pkg_name]}" ]]; then
      log "Discovered local package: $pkg_name (in $dir)"
      packages+=("$pkg_name")
      seen_packages["$pkg_name"]=1
    fi
  fi
done
shopt -u nullglob

if [ ${#packages[@]} -eq 0 ]; then
  log "Error: No packages found in packages.txt or local directories!"
  exit 1
fi

to_build=()
result_dir="/tmp/check-results"
rm -rf "$result_dir"
mkdir -p "$result_dir"

# Worker: check one package and record its verdict in $result_dir/$pkg.
# Must NOT write to stdout — stdout is reserved for GITHUB_OUTPUT.
# Verdict file contains exactly: "true" (build needed), "false" (up to date),
# or "error" (clone failed -> setup must abort, preserving the old fail-loud contract).
check_pkg() {
  local pkg="$1"
  local pkg_dir="/tmp/check-$pkg"
  local rc="$result_dir/$pkg"
  local pkg_needed=false

  log "Checking package: $pkg"

  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir"

  local local_dir
  local_dir="$(resolve_pkg_dir "$pkg")"

  if [ -n "$local_dir" ]; then
    log "  Using local package directory: $local_dir"
    cp -a "$local_dir/." "$pkg_dir/"
  else
    log "  Cloning from AUR..."
    git clone "https://aur.archlinux.org/${pkg}.git" "$pkg_dir" || {
      log "  Error: clone failed for $pkg"
      printf "error" > "$rc"
      return
    }
  fi

  # Fix ownership for builder
  chown -R builder:builder "$pkg_dir"

  pushd "$pkg_dir" >/dev/null

  # Fetch sources and update version (crucial for -git packages)
  # Run as builder without checking dependencies
  log "  Running makepkg -od to resolve version info..."
  sudo -u builder makepkg -od --noconfirm --nodeps >/dev/null 2>&1 || {
    log "  Warning: failed to update version for $pkg, proceeding with static version."
  }

  # Get expected package files
  pkgfiles=$(sudo -u builder makepkg --packagelist)

  for pkgfile in $pkgfiles; do
    pkgname=$(basename "$pkgfile")
    # Sanitize filename (replace colons with dots) to match GitHub Releases asset naming
    pkgname_clean=$(echo "$pkgname" | tr ':' '.')
    url="https://github.com/${REPO}/releases/download/${BRANCH}/${pkgname_clean}"

    # Check HTTP status of the package file on raw github
    status_code=$(curl -L -s -o /dev/null -w "%{http_code}" "$url")
    if [ "$status_code" -ne 200 ]; then
      log "    Package file $pkgname_clean not found (HTTP status: $status_code). Build is needed."
      pkg_needed=true
      break
    else
      log "    Package file $pkgname_clean already exists."
    fi
  done

  popd >/dev/null

  printf "%s" "$pkg_needed" > "$rc"
}

# Bounded concurrency: launch workers in background, keep at most CHECK_PARALLEL running.
CHECK_PARALLEL="${CHECK_PARALLEL:-8}"
running=0
for pkg in "${packages[@]}"; do
  check_pkg "$pkg" &
  running=$((running + 1))
  if [ "$running" -ge "$CHECK_PARALLEL" ]; then
    wait -n || true
    running=$((running - 1))
  fi
done
wait || true

# Aggregate results in deterministic input order (input order == packages.txt order).
# A missing or non-boolean verdict means the worker died before recording a result
# (e.g. makepkg failed under set -e); treat that as fatal rather than silently skipping
# the package, preserving the old fail-loud contract.
for pkg in "${packages[@]}"; do
  r="$(cat "$result_dir/$pkg" 2>/dev/null)"
  case "$r" in
    true)  to_build+=("$pkg") ;;
    false) ;;
    *)     log "Fatal: check failed for $pkg (no valid verdict: '${r:-<none>}')"; exit 1 ;;
  esac
done

# Output JSON array of packages to build and build status to stdout
json_array=$(jq -n -c '$ARGS.positional' --args "${to_build[@]}")
echo "packages_to_build=${json_array}"

if [ ${#to_build[@]} -gt 0 ]; then
  echo "build_needed=true"
else
  echo "build_needed=false"
fi
