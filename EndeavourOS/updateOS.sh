#!/usr/bin/env bash
# --------------------------------------------------------------
# EndeavourOS full system + AUR update without human interaction
# Prompts for reboot if a kernel or initramfs package was upgraded, otherwise does not prompt the user
# --------------------------------------------------------------

set -euo pipefail

# ----- Helper: show a tiny GUI dialog ---------------------------------
prompt_reboot() {
    # Uses zenity (installed by default on most EndeavourOS spins)
    zenity --question \
           --title="Reboot required" \
           --text="System packages were upgraded that usually require a reboot.\nDo you want to reboot now?" \
           --width=350
    if [[ $? -eq 0 ]]; then
        systemctl reboot
    fi
}

# ----- Remember currently installed kernel versions -------------------
# Compares before n after to decide whether a reboot is needed.
mapfile -t KERNEL_BEFORE < <(pacman -Qsq '^linux(|-.*)$' | sort)

# ----- Update the official repos (pacman) -----------------------------
# -Syu : sync + refresh + upgrade
# --noconfirm : never ask for confirmation so there is no need for human interations
sudo pacman -Syu --noconfirm

# ----- Update AUR packages (paru) ------------------------------------
# -Sua : upgrade all AUR packages
# --noconfirm : skip all prompts
# --skipreview : don’t open the build review UI because that shit is kinda annoying
# --cleanafter : clean the build directory after each install so it doesn't take 700 gb after 3 months of Linux usage
paru -Sua --noconfirm --skipreview --cleanafter

# ----- Check if any kernel or initramfs package changed ---------------
mapfile -t KERNEL_AFTER < <(pacman -Qsq '^linux(|-.*)$' | sort)

if ! diff <(printf "%s\n" "${KERNEL_BEFORE[@]}") <(printf "%s\n" "${KERNEL_AFTER[@]}") >/dev/null; then
    # No kernel package changed → no reboot needed
    exit 0
fi

# ----- Prompt the user ------------------------------------------------
prompt_reboot
