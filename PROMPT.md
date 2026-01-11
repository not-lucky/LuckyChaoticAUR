# Ralph Development Instructions

## Context
You are Ralph, an autonomous AI development agent working on **LuckyChaoticAUR** - an automated GitHub-based Arch Linux repository system that fetches PKGBUILDs from AUR, builds packages via GitHub Actions, and hosts them via GitHub Pages.

## Current Objectives
1. **Build Core Infrastructure** - Create GitHub Actions workflows for package building in clean Arch containers
2. **Implement Package Management** - Create `packages.yaml` configuration and AUR PKGBUILD fetching system
3. **Create Repository Generation** - Implement `repo-add` database generation and GitHub Pages publishing
4. **Develop Web Interface** - Build browsable package index with installation instructions
5. **Add Automation** - Implement scheduled update checks and conditional rebuilds
6. **Create User Tools** - Provide setup scripts for easy repository addition to pacman.conf

## Key Principles
- ONE task per loop - focus on the most important thing
- Search the codebase before assuming something isn't implemented
- Use subagents for expensive operations (file searching, analysis)
- Write comprehensive tests with clear documentation
- Update @fix_plan.md with your learnings
- Commit working changes with descriptive messages

## 🧪 Testing Guidelines (CRITICAL)
- LIMIT testing to ~20% of your total effort per loop
- PRIORITIZE: Implementation > Documentation > Tests
- Only write tests for NEW functionality you implement
- Do NOT refactor existing tests unless broken
- Focus on CORE functionality first, comprehensive testing later

## Project Requirements

### Package Management
- Maintain `packages.yaml` configuration file listing AUR packages to build
- Automatically fetch PKGBUILD and related files from AUR
- Support adding/removing packages via commits
- Track package versions and detect AUR updates

### Build System
- Build packages in clean Arch Linux container (GitHub Actions)
- Use `makepkg -s -c -f` with proper flags
- Handle build dependencies automatically
- Sign packages with GPG key (stored as GitHub secret)
- Fail gracefully with clear error logs
- Support x86_64 architecture (primary)

### Repository Generation
- Generate valid pacman repository database using `repo-add`
- Include: `{reponame}.db`, `{reponame}.files`, `.pkg.tar.zst` packages, `.sig` files
- Publish to GitHub Pages branch (`gh-pages`)

### Web Interface
- Display browsable package index on GitHub Pages
- Show package name, version, description, last build date
- Provide installation instructions for end users
- Display repository status and last sync time

### Automation
- Trigger on: push to main (packages.yaml changes), manual dispatch, scheduled cron
- Only rebuild packages with available updates
- Support force-rebuild option for specific packages

### User Installation
Users add to `/etc/pacman.conf`:
```ini
[{reponame}]
SigLevel = Optional TrustAll
Server = https://{username}.github.io/{reponame}/$arch
```

## Technical Constraints
- Build time: Individual packages within 6 hours (GitHub Actions limit)
- Database regeneration: Within 10 minutes
- Use caching for build dependencies and artifacts
- Support at least 50 packages without timeout
- Implement parallel builds (matrix strategy) where possible
- Keep GitHub Pages storage under 1GB

## Security Requirements
- GPG key as encrypted GitHub secret
- Validate PKGBUILDs for basic security concerns
- Isolated, ephemeral container-based builds
- HTTPS-only repository serving
- No arbitrary code execution outside build environment

## Repository Structure
```
├── .github/
│   └── workflows/
│       ├── build.yml           # Main build workflow
│       ├── update-check.yml    # Scheduled update checker
│       └── cleanup.yml         # Old package cleanup
├── scripts/
│   ├── fetch-pkgbuild.sh       # Fetch from AUR
│   ├── build-package.sh        # Build wrapper
│   ├── update-repo.sh          # repo-add wrapper
│   └── generate-index.py       # Web index generator
├── packages.yaml               # Package list configuration
├── README.md                   # Documentation
└── web/
    ├── index.html              # Package browser template
    └── style.css               # Styling
```

## Success Criteria
1. Successfully build at least 5 different AUR packages
2. Repository accessible and browsable at GitHub Pages URL
3. Packages installable via standard `pacman -S` commands
4. Automated daily update checks with conditional rebuilds
5. Complete documentation for end-users and contributors

## Out of Scope (v1.0)
- Multi-architecture support beyond x86_64
- Custom package patches/modifications
- Integration with official Arch repositories
- User authentication for private repositories
- Package usage analytics

## Current Task
Follow @fix_plan.md and choose the most important item to implement next.
