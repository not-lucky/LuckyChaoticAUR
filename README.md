# 🚀 LuckyChaoticAUR

**LuckyChaoticAUR** is an automated Arch User Repository (AUR) build system powered by GitHub Actions. It compiles selected AUR packages into a personal binary repository, hosting them directly via GitHub Releases for easy consumption on any Arch Linux system.

---

## 🌟 Key Features

- **Automated Builds**: Scheduled daily builds at 00:00 UTC to keep packages up-to-date.
- **Triggered Updates**: Automatically starts a build whenever you add a package to `packages.txt`.
- **Pre-compiled Binaries**: Saves time by avoiding long compilation times (especially for `-bin` or large packages) on your local machine.
- **High-Performance Parallel Builds**: Processes up to **4 packages simultaneously**, significantly reducing total build time for large repositories.
- **Smart Retention**: Automatically maintains only the **7 most recent releases**, preventing repository bloat and staying within GitHub storage limits.
- **Easy Management**: Add or remove packages by simply editing a text file.

---

## 🛠️ How It Works

The system follows a high-performance automated CI/CD pipeline:

1.  **Environment**: GitHub Actions spins up an `archlinux:base-devel` container.
2.  **Parallel Build Phase**: The `build.sh` script utilizes `xargs -P` to build multiple packages at once. 
    -   **Concurrency Lock**: It uses `flock` to manage `pacman` database access, ensuring dependency installation is safe while compilation happens in parallel.
    -   **Shallow Clones**: Uses `--depth 1` for faster AUR repository fetching.
3.  **Repository Indexing**: It uses `repo-add` to generate `luckyrepo.db` and `luckyrepo.files`.

4.  **Deployment**: Artifacts (`.pkg.tar.zst` and `.db`) are uploaded to a new GitHub Release with a timestamped tag (e.g., `repo-202603171200`).
5.  **Cleanup**: The `delete-older-releases` action prunes old releases, keeping your storage usage lean and constant.

---

## 📦 Using the Repository

To use your custom repository on any Arch Linux installation:

1.  **Edit your pacman configuration**:
    ```bash
    sudo nano /etc/pacman.conf
    ```

2.  **Add the repository section** at the end of the file:
    > **Note**: Replace `not-lucky` with your actual GitHub username.
    ```ini
    [luckyrepo]
    SigLevel = Optional TrustAll
    Server = https://github.com/not-lucky/LuckyChaoticAUR/releases/latest/download
    ```

3.  **Sync and Install**:
    ```bash
    sudo pacman -Sy
    sudo pacman -S paru-bin
    ```

---

## ➕ Adding New Packages

Expanding your repository is simple:

1.  Open [`packages.txt`](packages.txt) in this repository.
2.  Add the exact name of the AUR package (e.g., `google-chrome`, `visual-studio-code-bin`) on a new line.
3.  Commit and push your changes.
4.  **Monitor the build**: Go to the **Actions** tab in GitHub to see the build progress. Once finished, the new package will be available in the `latest` release.

---

## ⚙️ Project Structure

-   `.github/workflows/build-aur.yml`: The automation engine that handles scheduling, building, and cleanup.
-   `build.sh`: The core script that handles the Arch Linux build environment setup and `makepkg` execution.
-   `packages.txt`: Your wishlist of packages to be maintained in the repo.
-   `repo/`: (Generated during build) Contains the compiled packages and database files.

---

## ⚠️ Security & Maintenance

-   **GPG Signing**: By default, this setup uses `SigLevel = Optional TrustAll`. For production-grade security, consider setting up a GPG key in GitHub Secrets and updating `build.sh` to sign packages.
-   **Storage**: Each release typically consumes ~50-200MB depending on your package list. With a 7-day retention policy, your repository will stay well under 2GB indefinitely.
-   **Rate Limits**: GitHub Actions provides 2,000 free minutes per month for private repos (unlimited for public). This project typically uses ~5-10 minutes per build.

---

## 📜 License

This project is open-source. Feel free to fork and adapt it for your own personal Arch Linux needs!
