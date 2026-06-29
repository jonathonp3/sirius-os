#!/bin/bash

echo "🚀 Starting Sirius-OS First-Boot Optimization..."

# 1. Remove the stock Fedora Flatpak (The 'Old' version)
echo "🗑️ Removing stock Text Editor..."
flatpak uninstall --system -y org.gnome.TextEditor || true

# 2. Add the Wolf-OS Custom App Store
echo "📦 Connecting to Wolf-OS App Store..."
# We download your public GPG key to ensure the remote is trusted immediately
wget2 -q -O /tmp/wolf-os-apps.gpg https://raw.githubusercontent.com/jonathonp3/wolf-os-apps/main/wolf-os-apps.gpg

# Add the remote and import the key in one move
flatpak remote-add --system --if-not-exists --gpg-import=/tmp/wolf-os-apps.gpg wolf-os-apps https://jonathonp3.github.io/wolf-os-apps/

# 3. Install the Hand-Crafted version
echo "✨ Installing Wolf-OS Custom Text Editor..."
flatpak install --system -y wolf-os-apps org.gnome.TextEditor

# 4. Clean up
rm /tmp/wolf-os-apps.gpg


echo "✅ Sirius-OS first-boot tasks complete."
