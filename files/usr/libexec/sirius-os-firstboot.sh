#!/bin/bash
set -euo pipefail

# Configuration
REMOTE_NAME="wolf-os-apps"
REMOTE_URL="https://jonathonp3.github.io/wolf-os-apps/"
GPG_URL="https://raw.githubusercontent.com/jonathonp3/wolf-os-apps/main/wolf-os-apps.gpg"
GPG_FILE="/tmp/wolf-os-apps.gpg"
APP_ID="org.gnome.TextEditor"
FLAG_FILE="/etc/wolf-os/firstboot-done"

echo "🚀 Starting Sirius-OS Optimization..."

# 1. Skip if already successfully completed
if [[ -f "$FLAG_FILE" ]]; then
    echo "✅ Sirius-OS tasks already complete."
    exit 0
fi

# 2. Downloader
rm -f "$GPG_FILE"
echo "🔑 Downloading GPG key..."
if ! wget2 -q -O "$GPG_FILE" "$GPG_URL" && ! curl -fsSL -o "$GPG_FILE" "$GPG_URL"; then
    echo "❌ Failed to download key!"
    exit 1
fi

# 3. Flatpak Loop
SUCCESS_INSTALL=false
for i in {1..10}; do
    echo "📦 Connecting to Wolf-OS Store (Attempt $i/10)..."

    if err_msg=$(flatpak remote-add --system --if-not-exists --gpg-import="$GPG_FILE" "$REMOTE_NAME" "$REMOTE_URL" 2>&1); then

        CURRENT_ORIGIN=$(flatpak info --show-origin "$APP_ID" 2>/dev/null || echo "none")

        if [[ "$CURRENT_ORIGIN" != "$REMOTE_NAME" ]]; then
            echo "🔄 Replacing editor (not from $REMOTE_NAME)..."

            if flatpak info --system "$APP_ID" >/dev/null 2>&1; then
                flatpak uninstall --system -y "$APP_ID" || :
                flatpak uninstall --system -y --unused || :
            fi

            echo "📦 Installing $APP_ID from $REMOTE_NAME..."
            flatpak install --system -y "$REMOTE_NAME" "$APP_ID"
        else
            echo "✅ Wolf-OS Editor is already installed."
        fi

        SUCCESS_INSTALL=true
        break
    else
        if [[ "$err_msg" == *"lock"* ]]; then
            echo "⏳ Flatpak LOCKED. Waiting 20s..."
            sleep 20
        else
            echo "❌ Flatpak Error: $err_msg"
            exit 1
        fi
    fi
done

# 4. Finalize
if [ "$SUCCESS_INSTALL" = true ]; then
    echo "🎨 Applying theming overrides..."
    flatpak override --system --filesystem=xdg-config/gtk-4.0:ro || :
    flatpak override --system --filesystem=xdg-config/gtk-3.0:ro || :

    mkdir -p "$(dirname "$FLAG_FILE")"
    touch "$FLAG_FILE"
    rm -f "$GPG_FILE"
    echo "✨ Sirius-OS optimization complete!"
fi

