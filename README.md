# LuckyChaoticAUR

Automated Arch Linux package repository built and maintained via GitHub Actions and GitHub Releases.

## Adding Packages

### 1. AUR Packages
To build an AUR package, add the package name to `packages.txt`:
```text
google-chrome-beta
paru-bin
```

### 2. Local / In-Repository Packages
To build packages from local PKGBUILDs that are not on AUR (or custom modifications):
1. Create a directory containing the `PKGBUILD` and its source files directly in the repository root or inside `packages/` / `pkgs/`:
   ```
   LuckyChaoticAUR/
   ├── workbuddy-ai-bin/
   │   ├── PKGBUILD
   │   ├── .SRCINFO
   │   ├── workbuddy-ai.desktop
   │   └── workbuddy-ai.sh
   ├── packages.txt
   └── ...
   ```
2. (Optional) You can also explicitly add the package name (e.g. `workbuddy-ai-bin`) to `packages.txt`. In-repo packages are also auto-discovered automatically.
3. Commit and push your changes. Pushing to `master`/`main` automatically triggers the GitHub Actions build workflow.

## How It Works

1. **Check (`scripts/check_packages.sh`)**:
   - Compares the expected package version with assets currently in the GitHub Release (`repository` tag).
   - If a package is missing or updated, marks it for building.
2. **Build (`.github/workflows/build-aur.yml`)**:
   - Runs in an isolated `archlinux:base-devel` matrix container.
   - For local packages, copies all in-repo files into the build environment. For AUR packages, clones them from AUR.
   - Automatically configures the existing repository release as a pacman source to resolve in-repo dependencies.
3. **Publish (`scripts/update_repository.sh`)**:
   - Collects built `.pkg.tar.zst` packages, regenerates the pacman repository database (`lucky-chaotic.db.tar.zst`), and updates the GitHub Release.
