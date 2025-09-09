#!/usr/bin/env bash
# ------------------------------------------------------------
# Install apps that I usually always install on my computer by 
# using paru.
# If paru is missing, the script installs it first.
# ------------------------------------------------------------

set -euo pipefail   # safer scripting

# ---------- Helper: prnt status messages ----------
msg() {
    echo -e "\e[1;34m[+] $*\e[0m"
}

# ---------- Is user sudo/has sudo rights ? ----------
msg "Checking sudo privileges…"
if ! sudo -v; then
    echo "sudo authentication failed – aborting."
    exit 1
fi

# ---------- Install paru if it isn’t already ----------
if ! command -v paru &>/dev/null; then
    msg "paru not found – installing it now."

    # Install base-devel (needed for building AUR packages)
    sudo pacman -Sy --noconfirm --quiet base-devel git

    # Clone paru, build, and install
    TMPDIR=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$TMPDIR/paru"
    cd "$TMPDIR/paru"
    makepkg -si --noconfirm --quiet
    cd -
    rm -rf "$TMPDIR"

    msg "paru installed successfully."
else
    msg "paru is already installed."
fi

# ---------- List of packages to install that can be modified ----------
PKGS=(
    steam
    lutris
    discord
    r2modman
    heroic-games-launcher
)

# ---------- Install / upgrade the packages ----------
msg "Updating package databases (pacman)…"
sudo pacman -Sy --noconfirm --quiet

msg "Installing/upgrading gaming packages via paru (no prompts)…"
# --noconfirm : skip all confirmations
# --skipreview : don’t open the PKGBUILD review UI
# --cleanafter : clean the build dir after each install
paru -S "${PKGS[@]}" --noconfirm --skipreview --cleanafter

msg "Installation complete."
