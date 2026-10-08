#!/bin/bash
# Sirius-OS Optimization
#
# Runs once on first boot to migrate flatpaks on a Bazzite-based
# Sirius-OS system: cleans up orphaned Fedora-remote apps left by the
# Silverblue -> Bazzite rebase, installs the custom GNOME Text Editor
# flatpak from the Sirius-OS repository, and installs the Sirius-OS
# user app set from Flathub.
#
# Subsequent boots skip the script once the flag file exists.
#
# The script is safe to run multiple times. It exits without writing
# the flag if any step fails, so the next boot retries from the top.
# Every step is idempotent.
#
# Design notes:
#
#   - Nothing here hardcodes a flatpak branch or version. Installed
#     refs are discovered at runtime from `flatpak list` and
#     `flatpak pin`, and every uninstall/unpin is passed a
#     fully-qualified ref (ID/arch/branch). That avoids the
#     interactive "similar refs found" prompt and survives Fedora /
#     GNOME version bumps.
#
#   - Bazzite removes the Fedora flatpak remote from the base image
#     but does not uninstall the Fedora-origin apps inherited from
#     Silverblue. Those apps are orphaned: no updates, no security
#     patches, and `flatpak uninstall --unused` won't touch them
#     (it only handles runtimes). Section 2's else branch detects and
#     removes them.
#
#   - Loops that call `flatpak` in the body use `mapfile` to collect
#     refs into an array first, then iterate the array. A `while read`
#     loop over `flatpak list` breaks after the first iteration
#     because `flatpak uninstall` reads from the terminal in ways
#     that interrupt the loop. Array iteration has no live stream for
#     flatpak to interfere with.
#
#   - The custom editor's runtime (org.gnome.Platform) is pulled in
#     automatically as a dependency when the app is installed,
#     resolved from Flathub (ensured usable in section 1). It is NOT
#     installed explicitly, because an explicitly-installed runtime
#     gets auto-pinned by flatpak, which left stray pins behind.
#
# Exit codes:
#   0  — everything succeeded (flag written, or already present)
#   1  — a step failed; next boot will retry

set -euo pipefail

# --- Configuration ----------------------------------------------------
REMOTE_NAME="sirius-os-custom-editor"
REMOTE_URL="https://jonathonp3.github.io/sirius-os-custom-editor/"
GPG_URL="https://raw.githubusercontent.com/jonathonp3/sirius-os-custom-editor/main/sirius-os-custom-editor.gpg"
GPG_FILE="/tmp/sirius-os-custom-editor.gpg"
APP_ID="org.gnome.TextEditor"
FLAG_FILE="/etc/sirius-os/firstboot-done"

# Flathub — the source of the GNOME runtime the app depends on
FLATHUB_REMOTE="flathub"
FLATHUB_REPO_FILE="https://dl.flathub.org/repo/flathub.flatpakrepo"

# Fedora flatpak remote — present on Silverblue, absent on Bazzite.
# Section 2 handles both cases.
FEDORA_REMOTE="fedora"

# Regex prefix matching every Fedora platform runtime and extension.
# Used to find refs to unpin and uninstall WITHOUT naming specific
# branches or extensions — so this works across f44 -> f45 bumps and
# catches any new org.fedoraproject.Platform.* extension Fedora adds.
#
# Dots are escaped because this is used inside `grep -E`.
FEDORA_RUNTIME_PREFIX='org\.fedoraproject\.Platform'

# Apps served by the Fedora remote on Silverblue. Used only in the
# Silverblue path (section 2 if-branch) to uninstall them before the
# remote is removed.
#
# NOTE: org.gnome.TextEditor is intentionally NOT in this list. It is
# handled separately in section 2 stage 1c, because its removal must
# happen before the Fedora runtimes can be uninstalled, and its
# reinstall happens from the custom remote in section 6.
FEDORA_REMOTE_APPS=(
    org.gnome.Calculator
    org.gnome.Calendar
    org.gnome.Weather
    org.gnome.Contacts
    org.gnome.Maps
    org.gnome.Loupe
    org.gnome.Papers
    org.gnome.Characters
    org.gnome.Logs
    org.gnome.Snapshot
    org.gnome.baobab
    org.gnome.Connections
    org.gnome.font-viewer
    org.fedoraproject.MediaWriter
    org.gnome.NautilusPreviewer
    org.gnome.clocks
)

# Apps to remove outright, regardless of which remote they came from.
# Not reinstalled — they are replaced by an entry in SIRIUS_OS_APPS.
#
# org.gnome.Extensions    -> replaced by com.mattjakeman.ExtensionManager
#
# Removed in section 2 stage 1b, BEFORE the Fedora runtimes — because
# org.gnome.Extensions depends on org.fedoraproject.Platform, and the
# runtime can't be removed while this app still needs it.
REPLACED_APPS=(
    org.gnome.Extensions
)

# Sirius-OS user apps to install on first boot. Installed from Flathub.
#
# Note: Calendar, Papers, Logs, baobab, NautilusPreviewer, MediaWriter,
# and clocks also appear in FEDORA_REMOTE_APPS. On Silverblue they are
# removed in section 2 and reinstalled from Flathub in section 8. On
# Bazzite they are already present (orphaned) and get cleaned up +
# reinstalled. Either way, they end up from Flathub.
SIRIUS_OS_APPS=(
    # silverblue apps
    org.gnome.Calendar
    org.gnome.clocks
    org.gnome.Papers
    org.gnome.Logs
    org.gnome.baobab
    org.gnome.NautilusPreviewer

    # Communication and messaging
    com.discordapp.Discord
    im.riot.Riot

    # Office, notes, and productivity
    md.obsidian.Obsidian
    org.libreoffice.LibreOffice
    org.gnome.SimpleScan
    com.nextcloud.desktopclient.nextcloud

    # Graphics, images, and media
    org.gnome.gThumb
    org.gimp.GIMP

    # Music and streaming
    com.spotify.Client

    # Web browsers and email
    com.google.Chrome
    com.brave.Browser
    com.opera.Opera
    org.mozilla.thunderbird_esr

    # File sharing and downloads
    com.transmissionbt.Transmission

    # Games and game launchers
    # (Minecraft is handled separately, see below)
    org.vinegarhq.Sober
    com.modrinth.ModrinthApp

    # Security and password management
    org.keepassxc.KeePassXC

    # Flatpak management and utilities
    com.github.tchx84.Flatseal
    it.mijorus.gearlever
    xyz.xclicker.xclicker

    # GNOME tools and extensions
    com.mattjakeman.ExtensionManager

    # GPU monitoring and gaming tools
    io.github.benjamimgois.goverlay
)

# --- Helpers ----------------------------------------------------------
log()  { echo "🚀 $*"; }
warn() { echo "⚠️  $*" >&2; }
fail() { echo "❌ $*" >&2; exit 1; }

# Uninstall every installed ref whose ID matches the given regex.
#
# Refs are read from `flatpak list --columns=ref`, so they include the
# branch — no ambiguity, no prompts, no hardcoded versions.
#
# The pattern is followed by `([/.]|$)` so it matches both the base
# ref (`org.foo.Bar/x86_64/branch`) and any extension of it
# (`org.foo.Bar.Locale/...`, `org.foo.Bar.GL.default/...`).
#
# Uses mapfile + for to avoid the flatpak-in-a-while-read bug.
#
# Usage: uninstall_matching 'org\.example\.App'
uninstall_matching() {
    local pattern="$1"
    local refs
    mapfile -t refs < <(
        flatpak list --system --columns=ref 2>/dev/null \
            | grep -E "^${pattern}([/.]|$)" || true
    )
    for ref in "${refs[@]}"; do
        [[ -z "$ref" ]] && continue
        log "  Removing $ref..."
        flatpak uninstall --system -y "$ref" < /dev/null >/dev/null 2>&1 || true
    done
}

# Unpin every pinned ref whose ID matches the given regex.
#
# Refs are read from `flatpak pin`, so they include the branch.
#
# Uses mapfile + for to avoid the flatpak-in-a-while-read bug.
#
# Usage: unpin_matching 'org\.fedoraproject\.Platform'
unpin_matching() {
    local pattern="$1"
    local refs
    mapfile -t refs < <(
        flatpak pin --system 2>/dev/null \
            | awk '/^[[:space:]]+runtime\// {print $1}' \
            | grep -E "^runtime/${pattern}([/.]|$)" || true
    )
    for ref in "${refs[@]}"; do
        [[ -z "$ref" ]] && continue
        log "  Unpinning $ref..."
        flatpak pin --system --remove "$ref" >/dev/null 2>&1 || true
    done
}

# Remove every pin currently in the system. Used after a
# `remote-delete --force`, which can pin refs from ANY remote as a
# side effect. On a fresh first-boot system there are no user-set
# pins, so this is safe; the purpose is to leave the system clean.
unpin_all() {
    local refs
    mapfile -t refs < <(
        flatpak pin --system 2>/dev/null \
            | awk '/^[[:space:]]+runtime\// {print $1}' || true
    )
    for ref in "${refs[@]}"; do
        [[ -z "$ref" ]] && continue
        log "  Unpinning $ref..."
        flatpak pin --system --remove "$ref" >/dev/null 2>&1 || true
    done
}

# --- Skip if already successfully completed --------------------------
if [[ -f "$FLAG_FILE" ]]; then
    log "Sirius-OS tasks already complete."
    exit 0
fi

log "Starting Sirius-OS Optimization..."

# --- 1. Ensure Flathub is configured *and usable* --------------------
#
# A remote can be listed in `flatpak remotes` but still be broken —
# for example, if it was added without its GPG key. In that state,
# every `flatpak install` fails with "public key not found". The
# reliable test is `flatpak remote-ls`, which exercises the whole
# path: config, key, URL, signature.
#
# If the remote is missing or unreadable, we delete and re-add it
# from the `.flatpakrepo` file. That URL is what imports the GPG key.
# Adding the bare repo URL (without the `.flatpakrepo` suffix) does
# not import the key, which is how the broken state arises.
#
# The `--force` flag on remote-delete is required because the command
# would otherwise prompt interactively when the remote has installed
# refs. Under systemd there is no TTY, so the prompt would fail.
#
# This section MUST run before section 2: we do not strip Fedora apps
# until we know Flathub is available to reinstall them. It also must
# run before section 6, because the custom editor's runtime is pulled
# from Flathub as a dependency during that install.
log "Ensuring Flathub is configured and usable..."

if ! flatpak remote-ls --system "$FLATHUB_REMOTE" >/dev/null 2>&1; then
    log "Flathub is missing or unreadable; re-adding with its key..."

    flatpak remote-delete --system --force "$FLATHUB_REMOTE" 2>/dev/null || true

    if ! flatpak remote-add --system --if-not-exists \
            "$FLATHUB_REMOTE" "$FLATHUB_REPO_FILE"; then
        warn "Could not add Flathub; will retry on next boot."
        exit 1
    fi

    if ! flatpak remote-ls --system "$FLATHUB_REMOTE" >/dev/null 2>&1; then
        warn "Flathub added but still unreadable; will retry on next boot."
        exit 1
    fi

    log "Flathub is now configured and usable."
else
    log "Flathub is already configured and usable."
fi

# --- 2. Remove the Fedora flatpak remote, apps, and runtimes ---------
#
# Two paths depending on whether the Fedora remote is present:
#
#   if-branch  (Silverblue): the Fedora remote is present. Uninstall
#              its apps, then its runtimes, then delete the remote.
#
#   else-branch (Bazzite): the Fedora remote is gone from the base
#              image, but its apps are still installed and orphaned.
#              Detect them by comparing each app's origin against the
#              live remote list, remove them, then clean up the
#              Fedora runtimes and pins.
#
# Both paths end with Fedora refs gone and the system ready for the
# Flathub reinstall in section 8.
if flatpak remotes --system --columns=name 2>/dev/null | grep -qx "$FEDORA_REMOTE"; then
    # ============ Silverblue path ============
    log "Removing Fedora flatpak remote, apps, and runtimes..."

    # --- Stage 1a: Fedora apps ---
    log "Stage 1a: uninstalling apps from the Fedora remote..."
    for app in "${FEDORA_REMOTE_APPS[@]}"; do
        uninstall_matching "$app"
    done

    # --- Stage 1b: replaced apps ---
    log "Stage 1b: uninstalling replaced apps..."
    for app in "${REPLACED_APPS[@]}"; do
        uninstall_matching "$app"
    done

    # --- Stage 1c: TextEditor from Fedora ---
    TE_ORIGIN=$(flatpak info --show-origin "$APP_ID" 2>/dev/null || echo "none")
    if [[ "$TE_ORIGIN" == "$FEDORA_REMOTE" ]]; then
        log "Stage 1c: uninstalling $APP_ID from Fedora remote..."
        uninstall_matching "$APP_ID"
    else
        log "Stage 1c: $APP_ID is not from Fedora remote (origin: $TE_ORIGIN); skipping."
    fi

    # --- Stage 2: Fedora runtimes and extensions ---
    log "Stage 2: unpinning and uninstalling Fedora runtimes..."
    unpin_matching "$FEDORA_RUNTIME_PREFIX"
    uninstall_matching "$FEDORA_RUNTIME_PREFIX"

    # --- Stage 3: the remote itself ---
    log "Stage 3: deleting Fedora remote..."
    if ! flatpak remote-delete --system --force "$FEDORA_REMOTE"; then
        warn "Could not delete Fedora remote; will retry on next boot."
        exit 1
    fi

    flatpak uninstall --system -y --unused >/dev/null 2>&1 || true

    log "Clearing pins created by the remote deletion..."
    unpin_all

    log "Fedora remote removed."

else
    # ============ Bazzite path ============
    log "Fedora remote not present; converging orphaned refs..."

    # --- Remove orphaned apps ---
    #
    # Collect every app whose origin is no longer in the remote list,
    # then uninstall them one at a time.
    #
    # Uses mapfile + for (see design notes at top of file) to avoid
    # the flatpak-in-a-while-read bug.
    log "  Detecting orphaned apps..."
    local_remotes=$(flatpak remotes --system --columns=name 2>/dev/null || true)

    mapfile -t orphaned_apps < <(
        flatpak list --system --app --columns=application,origin 2>/dev/null \
            | while IFS=$'\t' read -r app origin; do
                [[ -z "$app" ]] && continue
                if ! printf '%s\n' "$local_remotes" | grep -qx "$origin"; then
                    echo "$app"
                fi
            done || true
    )

    if (( ${#orphaned_apps[@]} > 0 )); then
        log "  Removing ${#orphaned_apps[@]} orphaned app(s)..."
        for app in "${orphaned_apps[@]}"; do
            [[ -z "$app" ]] && continue
            log "    Removing $app..."
            flatpak uninstall --system -y "$app" < /dev/null >/dev/null 2>&1 || true
        done
    else
        log "  No orphaned apps found."
    fi

    # --- Unpin and uninstall Fedora runtimes ---
    log "  Cleaning up Fedora runtimes..."
    unpin_matching "$FEDORA_RUNTIME_PREFIX"
    uninstall_matching "$FEDORA_RUNTIME_PREFIX"

    # --- Sweep unused ---
    flatpak uninstall --system -y --unused >/dev/null 2>&1 || true

    # --- Clear any remaining Fedora pins ---
    flatpak pin --system 2>/dev/null \
        | awk '/^[[:space:]]+runtime\/org\.fedoraproject\./ {print $1}' \
        | while read -r ref; do
            flatpak pin --system --remove "$ref" >/dev/null 2>&1 || true
        done

    log "Orphaned Fedora refs removed."
fi

# --- 3. Download the custom repo's GPG key ---------------------------
rm -f "$GPG_FILE"
log "Downloading GPG key..."

if ! wget2 -q -O "$GPG_FILE" "$GPG_URL" 2>/dev/null; then
    if ! curl -fsSL -o "$GPG_FILE" "$GPG_URL" 2>/dev/null; then
        warn "Network unavailable; will retry on next boot."
        exit 1
    fi
fi

if [[ ! -s "$GPG_FILE" ]]; then
    warn "GPG key download produced an empty file; will retry on next boot."
    exit 1
fi

# --- 4. Add the custom flatpak remote (with retry for locks) ---------
for i in {1..10}; do
    log "Connecting to Sirius-OS store (attempt $i/10)..."

    if err_msg=$(flatpak remote-add --system --if-not-exists \
                    --gpg-import="$GPG_FILE" \
                    "$REMOTE_NAME" "$REMOTE_URL" 2>&1); then
        break
    fi

    if [[ "$err_msg" == *"lock"* ]]; then
        warn "Flatpak is locked; waiting 20s..."
        sleep 20
        continue
    fi

    warn "flatpak remote-add failed: $err_msg"
    exit 1
done

if ! flatpak remotes --system --columns=name | grep -qx "$REMOTE_NAME"; then
    warn "Remote was not registered after retries; will retry on next boot."
    exit 1
fi

# --- 5. Confirm the custom remote has the app ------------------------
if ! flatpak remote-ls --system "$REMOTE_NAME" --app --columns=application \
        | grep -qx "$APP_ID"; then
    warn "Remote is registered but $APP_ID is not listed; will retry on next boot."
    exit 1
fi

# --- 6. Install the custom editor ------------------------------------
#
# By this point (section 2) org.gnome.TextEditor has been uninstalled
# if it was from the Fedora remote. So this is a clean install from
# the custom remote.
#
# The app's runtime (org.gnome.Platform//<branch>) is resolved and
# pulled in automatically from Flathub as a dependency — Flathub was
# ensured usable in section 1. We deliberately do NOT install the
# runtime explicitly: an explicitly-installed runtime gets auto-pinned
# by flatpak, which left stray pins behind. Letting it come in as a
# dependency keeps it unpinned and still protected from --unused while
# the app needs it.
CURRENT_ORIGIN=$(flatpak info --show-origin "$APP_ID" 2>/dev/null || echo "none")

if [[ "$CURRENT_ORIGIN" == "$REMOTE_NAME" ]]; then
    log "$APP_ID is already installed from $REMOTE_NAME."
else
    if [[ "$CURRENT_ORIGIN" != "none" ]]; then
        log "Removing $APP_ID (currently from: $CURRENT_ORIGIN)..."
        flatpak uninstall --system -y "$APP_ID" < /dev/null >/dev/null 2>&1 || true
        flatpak uninstall --system -y --unused >/dev/null 2>&1 || true
    fi

    log "Installing $APP_ID from $REMOTE_NAME (runtime pulled from Flathub)..."
    if ! flatpak install --system -y "$REMOTE_NAME" "$APP_ID" < /dev/null >/dev/null 2>&1; then
        warn "Install failed; will retry on next boot."
        exit 1
    fi
fi

# --- 7. Verify the editor install actually landed --------------------
if ! flatpak info --system "$APP_ID" >/dev/null 2>&1; then
    warn "Install reported success but $APP_ID is not present; will retry."
    exit 1
fi

if [[ "$(flatpak info --show-origin "$APP_ID" 2>/dev/null)" != "$REMOTE_NAME" ]]; then
    warn "Installed but origin is not $REMOTE_NAME; will retry."
    exit 1
fi

# --- 8. Install Sirius-OS user apps from Flathub ---------------------
#
# These are the apps the Sirius-OS user relies on. They come from
# Flathub. Apps that are already installed (from any remote) are
# skipped by the `flatpak info` check, so this is a no-op for the
# GNOME utilities that ship with Silverblue and survived the rebase.
#
# com.mattjakeman.ExtensionManager is installed here as the
# replacement for org.gnome.Extensions (removed in section 2 stage 1b).
#
# Each app is installed individually so one failure does not block
# the others. Failures are collected and reported; if any app fails,
# the flag is not written and the next boot retries.
log "Installing Sirius-OS apps from Flathub (${#SIRIUS_OS_APPS[@]} apps)..."

SIRIUS_OS_FAILURES=()
for app in "${SIRIUS_OS_APPS[@]}"; do
    if flatpak info --system "$app" >/dev/null 2>&1; then
        # Already installed; skip silently
        continue
    fi

    log "  Installing $app..."
    if ! flatpak install --system -y flathub "$app" < /dev/null >/dev/null 2>&1; then
        warn "  Failed: $app"
        SIRIUS_OS_FAILURES+=("$app")
    fi
done

if (( ${#SIRIUS_OS_FAILURES[@]} > 0 )); then
    warn "Some Sirius-OS apps failed to install:"
    for app in "${SIRIUS_OS_FAILURES[@]}"; do
        warn "  - $app"
    done
    warn "Will not write flag; next boot will retry."
    exit 1
fi

log "All Sirius-OS apps installed."

# --- 9. Apply flatpak overrides --------------------------------------
#
# These are cosmetic (theming integration) and best-effort. A failure
# here does not prevent the flag from being written, because the
# apps themselves are already installed and working.
log "Applying theming overrides..."
flatpak override --system \
    --filesystem=xdg-config/gtk-4.0:ro \
    --filesystem=xdg-config/gtk-3.0:ro >/dev/null 2>&1 || true

flatpak override --system \
    --filesystem=/run/dbus/system_bus_socket \
    --talk-name=org.freedesktop.secrets \
    --env=PASSWORD_STORE=gnome-libsecret \
    im.riot.Riot >/dev/null 2>&1 || true

# --- 10. Finalize ----------------------------------------------------
# All critical steps have succeeded. Write the flag so the next boot
# skips this script.
mkdir -p "$(dirname "$FLAG_FILE")"
touch "$FLAG_FILE"
rm -f "$GPG_FILE"

log "Sirius-OS optimization complete."
