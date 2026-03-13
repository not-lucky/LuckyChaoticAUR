# Custom AUR Build System

This repository automatically builds selected Arch User Repository (AUR) packages using GitHub Actions and creates a Pacman repository ready for consumption.

## Usage

To use the automatically built packages on your Arch Linux system, you need to add this custom repository to your `pacman.conf`.

1. Open your `/etc/pacman.conf` file with root privileges:
   ```bash
   sudo nano /etc/pacman.conf
   ```

2. Add the following lines to the very end of the file. Note that we need to use a GitHub release asset URL. Replace `not-lucky` with your GitHub username if you've forked this repository. Keep the `luckyrepo` as the repository name since that's what is configured in `build.sh`.
   
   *Since GitHub releases generate dynamic URLs based on the tag, we can use the `latest` tag provided by GitHub to always grab the newest database.*

   ```ini
   [luckyrepo]
   SigLevel = Optional TrustAll
   Server = https://github.com/not-lucky/LuckyChaoticAUR/releases/latest/download
   ```

3. Save the file and exit.

4. Update your pacman databases and synchronize:
   ```bash
   sudo pacman -Sy
   ```

5. You can now install the packages defined in `packages.txt` directly via pacman! For example:
   ```bash
   sudo pacman -S paru-bin
   ```

## Adding new packages

To add a new AUR package to the build system:
1. Open [`packages.txt`](packages.txt)
2. Add the exact name of the AUR package on a new line.
3. Commit and push the changes. The GitHub Action will automatically trigger and build the new package.
