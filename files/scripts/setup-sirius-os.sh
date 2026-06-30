#!/bin/bash
set -euo pipefail

echo "🚀 Starting Serius-OS Master Assembly..."

# --- 1. PRE-INSTALL IDENTITY ---
# Create groups in the build factory
groupadd -r piavpn || true
groupadd -r piahnsd || true
groupadd -r docker || true
groupadd -r libvirt-qemu || true
groupadd -r virtnetwork || true

# --- 2. EXTRACTION ---
mkdir -p /usr/libexec/piavpn
# Note: In Zeta-OS recipe, we placed the tarball at /tmp/pia-backup.tar.xz
tar -xpJf /tmp/pia-backup.tar.xz -C /usr/libexec/piavpn/

# --- 3: SYSTEM INTEGRATION ---
mkdir -p /usr/lib/systemd/system /usr/lib/NetworkManager/conf.d /usr/share/applications /usr/share/pixmaps

cp /usr/libexec/piavpn/etc/systemd/system/piavpn.service /usr/lib/systemd/system/piavpn.service
# NetworkManager drop-ins under /usr/lib are shipped as part of the immutable image
# so the config is always present even if /etc isn't populated/persisted the way we expect.
cp /usr/libexec/piavpn/etc/NetworkManager/conf.d/wgpia.conf /usr/lib/NetworkManager/conf.d/wgpia.conf
cp /usr/libexec/piavpn/usr/share/applications/piavpn.desktop /usr/share/applications/piavpn.desktop
cp /usr/libexec/piavpn/usr/share/pixmaps/piavpn.png /usr/share/pixmaps/piavpn.png

# Create native symlinks in the build's /usr/bin path
# This makes the commands available system-wide (e.g. typing 'piactl' in terminal)
ln -sf /usr/libexec/piavpn/opt/piavpn/bin/piactl /usr/bin/piactl
ln -sf /usr/libexec/piavpn/opt/piavpn/bin/pia-daemon /usr/bin/pia-daemon
ln -sf /usr/libexec/piavpn/opt/piavpn/bin/pia-client /usr/bin/pia-client
ln -sf /usr/libexec/piavpn/opt/piavpn/bin/pia-unbound /usr/bin/pia-unbound

# Set Path
sed -i '/\[Service\]/a WorkingDirectory=/opt/piavpn' /usr/lib/systemd/system/piavpn.service

# --- 4. PERMISSIONS ----
setcap 'cap_net_bind_service=+ep' /usr/libexec/piavpn/opt/piavpn/bin/pia-unbound || true

# 
chown root:piavpn /usr/libexec/piavpn/opt/piavpn/bin/pia-client
chown root:piavpn /usr/libexec/piavpn/opt/piavpn/bin/piactl
chmod 755 /usr/libexec/piavpn/opt/piavpn/bin/pia-client
chmod 755 /usr/libexec/piavpn/opt/piavpn/bin/piactl

# Ensure clean up script is executable
chmod +x /usr/libexec/sirius-os-firstboot.sh

# --- 2. WINBOAT AUTO-UPDATE (Safe & Integrated Version) ---
echo "🚢 Finding latest Winboat..."

WINBOAT_URL=$(curl -s https://api.github.com/repos/TibixDev/winboat/releases/latest | grep "browser_download_url.*x86_64.rpm" | cut -d '"' -f 4)

if [ -n "$WINBOAT_URL" ]; then
    echo "✅ Found: $WINBOAT_URL"
    curl -L "$WINBOAT_URL" -o /tmp/winboat.rpm
    
    echo "📦 Installing Winboat RPM..."
    # Only install once!
    rpm -i --noscripts /tmp/winboat.rpm || echo "⚠️ Warning: Winboat install failed, continuing..."
    
    echo "🔧 Moving Winboat to Immutable Storage (The 'Truth')..."
    # Move the 'Truth' to immutable storage (like we did for PIA)
    mkdir -p /usr/libexec/winboat
    cp -r /opt/winboat/* /usr/libexec/winboat/

    # Now that the files are safely in /usr/libexec, we can remove the /opt version 
    # (tmpfiles.d will recreate /opt/winboat as a link on boot)
    rm -rf /opt/winboat

    echo "🔧 Performing manual integration..."
    
    # 1. Create the binary link pointing to our immutable 'Truth'
    ln -sf /usr/libexec/winboat/winboat /usr/bin/winboat
    
    # 2. Set sandbox permissions on the immutable version
    if [ -f /usr/libexec/winboat/chrome-sandbox ]; then
        chmod 4755 /usr/libexec/winboat/chrome-sandbox || true
    fi
    
    # 3. FIX MISSING ICON/DESKTOP ENTRY
    # Ensure the desktop file is in the correct location
    if [ -f /usr/libexec/winboat/resources/winboat.desktop ]; then
        cp -f /usr/libexec/winboat/resources/winboat.desktop /usr/share/applications/winboat.desktop
        # Fix the path inside the desktop file to use our new location
        sed -i 's|Exec=/opt/winboat/winboat|Exec=/usr/bin/winboat|g' /usr/share/applications/winboat.desktop
    fi
    
    # Force the databases to update so the icon appears
    if [ -d /usr/share/icons/hicolor ]; then
        gtk-update-icon-cache /usr/share/icons/hicolor || true
    fi
    update-mime-database /usr/share/mime || true
    update-desktop-database /usr/share/applications || true
    
    # 4. Clean up the installer
    rm /tmp/winboat.rpm
    
    echo "✅ Winboat integration complete."
else
    echo "⚠️ Warning: Could not find Winboat URL."
fi

# Update the Binary Symlink
ln -sf /usr/libexec/winboat/winboat /usr/bin/winboat 

# --- 5. FINALISE --- 
systemctl enable libvirtd.service virtlogd.service virtnetworkd.service virtstoraged.service virtnodedevd.socket piavpn.service sshd.service docker.service sirius-os-cleanup.service piavpn-tmpfiles.service

echo "✅ Sirius-OS Custom Assembly Complete!"
