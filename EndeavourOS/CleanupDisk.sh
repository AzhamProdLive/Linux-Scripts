#!/usr/bin/env bash
# ------------------------------------------------------------
# Disk‑space cleanup script for Arch based distros
# Pacman & Paru cache cleanup
# Orphaned packages & old kernels removal
# Temporary files, journal logs, thumbnail cache
# Flatpak runtime pruning
# SSD TRIM (fstrim) on all mounted SSDs
# ------------------------------------------------------------

set -euo pipefail          # safer execution
IFS=$'\n\t'                # sane word splitting

# ---------- Helper functions ----------
log()   { echo -e "\e[1;34][*] $*\e[0m"; }
warn()  { echo -e "\e[1;33][!] $*\e[0m"; }
error() { echo -e "\e[1;31][X] $*\e[0m"; }

# Keep track of freed space
freed_bytes=0
add_freed() { (( freed_bytes+=${1:-0} )); }

# Convert bytes into human readable numbers
human() {
    local b=$1
    awk '
    function human(x) {
        s="B KiB MiB GiB TiB PiB EiB"
        while (x>=1024 && ++i) x/=1024
        printf "%.1f %s", x, substr(s,i*4+1,4)
    }
    {print human($1)}' <<<"$b"
}

# ---------- Pacman / Paru cache cleanup ----------
log "Cleaning Pacman cache (uninstalled packages)."
# Remove uninstalled package files, keep the 2 newest versions of each packages
sudo paccache -rk2 -v || warn "paccache not found – skipping Pacman cache"

log "Removing orphaned packages."
orphans=$(pacman -Qtdq || true)
if [[ -n $orphans ]]; then
    sudo pacman -Rns --noconfirm $orphans
else
    log "No orphaned packages found."
fi

log "Cleaning Paru cache."
if command -v paru &>/dev/null; then
    # Paru stores its cache in ~/.cache/paru
    paru_cache_dir="${HOME}/.cache/paru"
    if [[ -d $paru_cache_dir ]]; then
        size_before=$(du -sb "$paru_cache_dir" | cut -f1)
        rm -rf "${paru_cache_dir:?}"/*
        size_after=$(du -sb "$paru_cache_dir" | cut -f1)
        add_freed $((size_before-size_after))
        log "Paru cache cleared ($(human $size_before) → $(human $size_after))."
    else
        log "Paru cache directory not found."
    fi
else
    log "Paru not installed – skipping Paru cache."
fi

# ---------- Old kernel removal ----------
log "Removing old kernels (but keeping the newest/running one)."
# List installed kernels (linux, linux-lts, linux-zen, etc.)
kernels=$(pacman -Qsq '^linux(|-[a-z]+)?$')
current_kernel=$(uname -r)

for k in $kernels; do
    # Skip the currently running kernel
    if [[ $k == "$current_kernel"* ]]; then
        continue
    fi
    # Keep the newest version of each kernel flavour
    newest=$(pacman -Qsq "^${k%%-*}" | sort -V | tail -n1)
    if [[ $k != "$newest" ]]; then
        log "Removing old kernel package: $k"
        sudo pacman -Rns --noconfirm "$k"
    fi
done

# ---------- System temporary files ----------
log "Cleaning /tmp (files older than 24 h)."
sudo find /tmp -mindepth 1 -mtime +1 -exec rm -rf {} +

log "Cleaning journal logs older than 2 weeks."
# Keep 2 weeks of logs, purge the rest
sudo journalctl --vacuum-time=2weeks

log "Cleaning user thumbnail cache."
thumb_dir="${HOME}/.cache/thumbnails"
if [[ -d $thumb_dir ]]; then
    size_before=$(du -sb "$thumb_dir" | cut -f1)
    rm -rf "${thumb_dir:?}"/*
    size_after=$(du -sb "$thumb_dir" | cut -f1)
    add_freed $((size_before-size_after))
    log "Thumbnail cache cleared ($(human $size_before) → $(human $size_after))."
fi

# ---------- Flatpak cleanup ----------
if command -v flatpak &>/dev/null; then
    log "Pruning unused Flatpak runtimes and removing old refs..."
    flatpak uninstall --unused -y
    flatpak repair -y
else
    log "Flatpak not installed – skipping."
fi

# ---------- SSD TRIM (fstrim) ----------
log "Running fstrim on all mounted SSDs..."
while read -r dev mount fstype opts _; do
    # Only consider ext4, btrfs, xfs, vfat, ntfs, etc.; ignore swap, pseudo‑fs, might drop ntfs as it can cause issues with dual booting ?
    [[ $fstype =~ ^(ext[234]|btrfs|xfs|vfat|ntfs)$ ]] || continue
    # Detect SSDs via /sys/block/<dev>/queue/rotational (0 = SSD)
    block=$(basename "$dev")
    if [[ -e "/sys/block/$block/queue/rotational" ]] && [[ $(cat "/sys/block/$block/queue/rotational") -eq 0 ]]; then
        log "Trimming $mount (device $dev)..."
        sudo fstrim -av "$mount"
    fi
done < <(findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS)

# ---------- Summary ----------
log "Disk‑cleanup completed."
if (( freed_bytes > 0 )); then
    echo -e "\e[1;32]Total space reclaimed: $(human $freed_bytes)\e[0m"
else
    echo -e "\e[1;32]No measurable space reclaimed (most caches were already empty).\e[0m"
fi
