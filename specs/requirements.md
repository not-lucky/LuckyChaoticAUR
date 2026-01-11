# Technical Specifications

## System Overview

LuckyChaoticAUR is an automated Arch Linux package repository system that:
1. Fetches PKGBUILD files from the Arch User Repository (AUR)
2. Builds packages using GitHub Actions workflows
3. Hosts compiled packages as a personal pacman repository via GitHub Pages

**Repository URL Format:** `https://{username}.github.io/{reponame}`

---

## System Architecture

### Component Diagram
```
┌─────────────────────────────────────────────────────────────────────┐
│                         GitHub Repository                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐  │
│  │ packages.yaml│───▶│  GitHub Actions  │───▶│   gh-pages       │  │
│  │ (config)     │    │  (build system)  │    │   (repository)   │  │
│  └──────────────┘    └──────────────────┘    └──────────────────┘  │
│                              │                        │              │
│                              ▼                        ▼              │
│                      ┌──────────────┐         ┌──────────────┐      │
│                      │ Arch Linux   │         │ GitHub Pages │      │
│                      │ Container    │         │ Web Server   │      │
│                      └──────────────┘         └──────────────┘      │
│                                                       │              │
└───────────────────────────────────────────────────────│──────────────┘
                                                        │
                                                        ▼
                                               ┌──────────────────┐
                                               │  End User        │
                                               │  (pacman client) │
                                               └──────────────────┘
```

### Data Flow
1. **Configuration Phase**: User defines packages in `packages.yaml`
2. **Fetch Phase**: Scripts retrieve PKGBUILD from AUR
3. **Build Phase**: GitHub Actions builds packages in Arch container
4. **Publish Phase**: Built packages deployed to GitHub Pages
5. **Consume Phase**: Users install packages via `pacman -S`

---

## Data Models

### Package Configuration (`packages.yaml`)

```yaml
repository:
  name: string                    # Repository name (used in pacman.conf)
  maintainer: string              # "Name <email@example.com>"
  description: string             # Optional repository description

packages:
  - name: string                  # AUR package name (required)
    aur: boolean                  # Must be true for AUR packages
    skip_pgp_check: boolean       # Optional: skip PGP signature verification
    force_rebuild: boolean        # Optional: force rebuild even if up-to-date
    custom_flags: string[]        # Optional: additional makepkg flags
```

**Example:**
```yaml
repository:
  name: luckychaoticaur
  maintainer: "Lucky <lucky@example.com>"

packages:
  - name: yay
    aur: true
  - name: visual-studio-code-bin
    aur: true
  - name: spotify
    aur: true
    skip_pgp_check: true
  - name: brave-bin
    aur: true
```

### Package Metadata (Internal)

```yaml
# Generated during build, stored for web index
package:
  name: string
  version: string
  description: string
  url: string
  license: string[]
  depends: string[]
  makedepends: string[]
  size: number                    # Installed size in bytes
  compressed_size: number         # Package file size
  build_date: timestamp
  packager: string
  arch: string                    # x86_64
  filename: string                # package-name-version-arch.pkg.tar.zst
```

---

## API Specifications

### AUR RPC API (External)

**Base URL:** `https://aur.archlinux.org/rpc/v5`

**Endpoints Used:**
- `GET /info?arg[]={package}` - Get package information
- `GET /search?arg={query}` - Search packages (optional)

**Response Format:**
```json
{
  "version": 5,
  "type": "multiinfo",
  "resultcount": 1,
  "results": [{
    "ID": 123456,
    "Name": "package-name",
    "Version": "1.2.3-1",
    "Description": "Package description",
    "URL": "https://upstream.url",
    "URLPath": "/cgit/aur.git/snapshot/package-name.tar.gz",
    "LastModified": 1234567890,
    "OutOfDate": null
  }]
}
```

### AUR Git Repository

**Clone URL:** `https://aur.archlinux.org/{package}.git`

Used to fetch:
- `PKGBUILD`
- `.SRCINFO`
- Any additional source files (patches, install scripts)

---

## GitHub Actions Workflow Specifications

### Main Build Workflow (`build.yml`)

**Triggers:**
- `push` to `main` branch (when `packages.yaml` changes)
- `workflow_dispatch` (manual trigger with optional inputs)
- `schedule` (cron for automated updates)

**Inputs (workflow_dispatch):**
- `package`: string - Specific package to rebuild (optional)
- `force`: boolean - Force rebuild even if up-to-date

**Jobs:**
1. **Detect Changes**: Determine which packages need building
2. **Build Matrix**: Build packages in parallel (matrix strategy)
3. **Generate Repository**: Run `repo-add` and create database
4. **Deploy**: Push to `gh-pages` branch

**Container Environment:**
- Image: `archlinux:latest`
- Required packages: `base-devel`, `git`, `gnupg`
- User: Non-root build user (makepkg requirement)

### Update Check Workflow (`update-check.yml`)

**Triggers:**
- `schedule`: `cron: '0 6 * * *'` (daily at 6 AM UTC)

**Logic:**
1. Fetch current versions from repository metadata
2. Query AUR API for latest versions
3. Compare versions
4. Trigger build workflow for outdated packages

### Cleanup Workflow (`cleanup.yml`)

**Triggers:**
- `schedule`: Weekly
- After successful builds

**Logic:**
1. Keep only N most recent versions per package (default: 2)
2. Remove orphaned packages (no longer in `packages.yaml`)
3. Update repository database

---

## Script Specifications

### `scripts/fetch-pkgbuild.sh`

**Purpose:** Fetch PKGBUILD and related files from AUR

**Arguments:**
- `$1`: Package name

**Output:**
- Creates `./aur/{package}/` directory
- Contains: PKGBUILD, .SRCINFO, additional sources

**Exit Codes:**
- `0`: Success
- `1`: Package not found
- `2`: Network error
- `3`: Git clone failed

### `scripts/build-package.sh`

**Purpose:** Build package using makepkg

**Arguments:**
- `$1`: Package name
- `$2`: Build directory path
- `$3`: Output directory path

**Environment Variables:**
- `GPGKEY`: GPG key ID for signing
- `SKIP_PGP_CHECK`: If set, add `--skippgpcheck` flag

**makepkg Flags:**
- `-s`: Sync dependencies
- `-c`: Clean up after build
- `-f`: Force rebuild
- `--noconfirm`: Non-interactive
- `--sign`: Sign package (if GPGKEY set)

**Exit Codes:**
- `0`: Success
- `1`: Build failed
- `2`: Dependency resolution failed

### `scripts/update-repo.sh`

**Purpose:** Generate pacman repository database

**Arguments:**
- `$1`: Repository name
- `$2`: Package directory path

**Commands Executed:**
```bash
repo-add --verify --sign ${reponame}.db.tar.gz *.pkg.tar.zst
```

**Output Files:**
- `{reponame}.db` (symlink to .db.tar.gz)
- `{reponame}.db.tar.gz`
- `{reponame}.files` (symlink to .files.tar.gz)
- `{reponame}.files.tar.gz`
- `{reponame}.db.sig`
- `{reponame}.files.sig`

### `scripts/generate-index.py`

**Purpose:** Generate HTML package index for GitHub Pages

**Input:**
- Package metadata from `.SRCINFO` files
- Build timestamps
- Repository configuration

**Output:**
- `index.html` with package listing
- JSON metadata file for programmatic access

---

## User Interface Requirements

### Package Browser (GitHub Pages)

**Required Elements:**
1. Repository name and description header
2. Package count and last sync time
3. Searchable/filterable package table
4. Per-package display:
   - Name (link to AUR page)
   - Version
   - Description
   - Last built date
   - Download link

**Installation Instructions Section:**
```
## Installation

1. Add to /etc/pacman.conf:

[{reponame}]
SigLevel = Optional TrustAll
Server = https://{username}.github.io/{reponame}/$arch

2. Sync and install:

sudo pacman -Sy {package-name}
```

---

## Performance Requirements

| Metric | Requirement |
|--------|-------------|
| Individual package build | < 6 hours |
| Repository database regeneration | < 10 minutes |
| Packages supported | ≥ 50 |
| GitHub Pages storage | < 1 GB |
| Build cache efficiency | > 50% time savings |

---

## Security Specifications

### GPG Signing

**Key Storage:**
- Private key: GitHub Secret `GPG_PRIVATE_KEY` (base64 encoded)
- Passphrase: GitHub Secret `GPG_PASSPHRASE`

**Key Setup in Workflow:**
```bash
echo "$GPG_PRIVATE_KEY" | base64 -d | gpg --import
echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 ...
```

**Signed Artifacts:**
- Individual packages: `*.pkg.tar.zst.sig`
- Repository database: `*.db.sig`, `*.files.sig`

### PKGBUILD Validation

**Basic Security Checks:**
1. No external script downloads from untrusted sources
2. No modification of files outside build directory
3. Validate checksums present for sources
4. Flag packages with `install` scripts for review

### Build Isolation

- Fresh container per build
- No persistent state between builds
- No network access during package phase (optional, configurable)
- Non-root user for makepkg execution

---

## Integration Requirements

### GitHub Features Used
- GitHub Actions (CI/CD)
- GitHub Pages (hosting)
- GitHub Secrets (credential storage)
- Git LFS (optional, for large packages)

### External Dependencies
- AUR API (`aur.archlinux.org`)
- Arch Linux mirrors (for build dependencies)
- Arch Linux container image (`archlinux:latest`)

---

## Error Handling

### Retry Logic

| Failure Type | Retry Count | Delay |
|--------------|-------------|-------|
| Network timeout | 3 | Exponential (1s, 2s, 4s) |
| AUR API error | 3 | 5s |
| Mirror sync | 2 | 10s |
| Build failure | 0 | N/A (fail fast) |

### Failure Modes

1. **Package build failure**: Log error, continue with other packages, report in summary
2. **Repository corruption**: Rollback to previous gh-pages commit
3. **AUR unavailable**: Skip update check, use cached PKGBUILDs
4. **GitHub Pages deployment failure**: Retry, alert maintainer

---

## File Structure

```
LuckyChaoticAUR/
├── .github/
│   └── workflows/
│       ├── build.yml              # Main build workflow
│       ├── update-check.yml       # Scheduled update checker
│       └── cleanup.yml            # Old package cleanup
├── scripts/
│   ├── fetch-pkgbuild.sh          # Fetch PKGBUILD from AUR
│   ├── build-package.sh           # Build wrapper script
│   ├── update-repo.sh             # repo-add wrapper
│   ├── generate-index.py          # Web index generator
│   └── check-updates.sh           # Version comparison script
├── web/
│   ├── index.html                 # Package browser template
│   ├── style.css                  # Styling
│   └── packages.json              # Machine-readable package list
├── specs/
│   └── requirements.md            # This file
├── packages.yaml                  # Package list configuration
├── README.md                      # User documentation
├── PROMPT.md                      # Ralph development instructions
├── @fix_plan.md                   # Task tracking
└── @AGENT.md                      # Build/development instructions
```

---

## Compatibility Requirements

| Component | Version/Requirement |
|-----------|---------------------|
| Arch Linux | Current stable |
| pacman | 6.0+ |
| makepkg | 6.0+ |
| GitHub Actions | Ubuntu-latest runners |
| Python | 3.10+ (for scripts) |
| Bash | 5.0+ |

---

## Success Criteria

1. **Build 5+ AUR packages successfully**
   - Verification: Packages appear in repository database
   - Verification: Packages installable via pacman

2. **Repository accessible at GitHub Pages URL**
   - Verification: HTTPS access works
   - Verification: Database files downloadable

3. **Packages installable via `pacman -S`**
   - Verification: Test installation on clean Arch system
   - Verification: Dependencies resolved correctly

4. **Automated daily update checks**
   - Verification: Cron workflow runs successfully
   - Verification: Outdated packages trigger rebuilds

5. **Complete documentation**
   - Verification: README covers setup, usage, contribution
   - Verification: Web interface shows installation instructions
