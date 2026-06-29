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

# --- 2. WINBOAT AUTO-UPDATE (Safe Version) ---
echo "🚢 Finding latest Winboat..."

# 1. Get the URL for the latest RPM
WINBOAT_URL=$(curl -s https://api.github.com/repos/TibixDev/winboat/releases/latest | grep "browser_download_url.*x86_64.rpm" | cut -d '"' -f 4)

if [ -n "$WINBOAT_URL" ]; then
    echo "✅ Found: $WINBOAT_URL"
    # 2. Download it to a temp location
    curl -L "$WINBOAT_URL" -o /tmp/winboat.rpm
    
    # 3. Install using rpm directly with --noscripts to avoid the 'unshare' error
    # This installs the files without running the problematic post-install scripts
    rpm -i --noscripts /tmp/winboat.rpm || echo "⚠️ Warning: Winboat install failed, continuing..."
    
    # 4. Clean up
    rm /tmp/winboat.rpm
else
    echo "⚠️ Warning: Could not find Winboat."
fi

# --- 5. FINALISE --- 
systemctl enable libvirtd.service virtlogd.service virtnetworkd.service virtstoraged.service virtnodedevd.socket piavpn.service sshd.service docker.service sirius-os-cleanup.service piavpn-tmpfiles.service

echo "✅ Sirius-OS Custom Assembly Complete!"
