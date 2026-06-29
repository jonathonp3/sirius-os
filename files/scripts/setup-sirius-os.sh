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

# --- 2. WINBOAT AUTO-UPDATE (Fail-Safe Version) ---
echo "🚢 Attempting to find the latest Winboat release..."

# Use a subshell and '|| true' to ensure the variable assignment prevents the script from crashing
WINBOAT_URL=$(curl -s https://api.github.com/repos/TibixDev/winboat/releases/latest | \
              grep "browser_download_url.*x86_64.rpm" | \
              cut -d '"' -f 4 || echo "")

if [ -n "$WINBOAT_URL" ]; then
    echo "✅ Found Winboat: $WINBOAT_URL"
    echo "📦 Attempting to install Winboat RPM..."
    
    # Use '|| echo ...' so if the download or install fails, the build carries on
    dnf install -y "$WINBOAT_URL" || echo "⚠️ Warning: Winboat installation failed, but continuing build."
else
    echo "⚠️ Warning: Could not find Winboat download URL. Winboat will not be included in this build."
fi

# --- 3. EXTRACTION ---
mkdir -p /usr/libexec/piavpn
# Note: In Zeta-OS recipe, we placed the tarball at /tmp/pia-backup.tar.xz
tar -xpJf /tmp/pia-backup.tar.xz -C /usr/libexec/piavpn/

# --- 4: SYSTEM INTEGRATION ---
mkdir -p /usr/lib/systemd/system /usr/lib/NetworkManager/conf.d /usr/share/applications /usr/share/pixmaps

cp /usr/libexec/piavpn/etc/systemd/system/piavpn.service /usr/lib/systemd/system/piavpn.service
# NetworkManager drop-ins under /usr/lib are shipped as part of the immutable image
# so the config is always present even if /etc isn't populated/persisted the way we expect.
cp /usr/libexec/piavpn/etc/NetworkManager/conf.d/wgpia.conf /usr/lib/NetworkManager/conf.d/wgpia.conf
cp /usr/libexec/piavpn/usr/share/applications/piavpn.desktop /usr/share/applications/piavpn.desktop
cp /usr/libexec/piavpn/usr/share/pixmaps/piavpn.png /usr/share/pixmaps/piavpn.png

# Set Path
sed -i '/\[Service\]/a WorkingDirectory=/opt/piavpn' /usr/lib/systemd/system/piavpn.service

# --- 5. PERMISSIONS ----
setcap 'cap_net_bind_service=+ep' /usr/libexec/piavpn/opt/piavpn/bin/pia-unbound || true

# 
chown root:piavpn /usr/libexec/piavpn/opt/piavpn/bin/pia-client
chown root:piavpn /usr/libexec/piavpn/opt/piavpn/bin/piactl
chmod 755 /usr/libexec/piavpn/opt/piavpn/bin/pia-client
chmod 755 /usr/libexec/piavpn/opt/piavpn/bin/piactl

# Ensure clean up script is executable
chmod +x /usr/libexec/sirius-os-firstboot.sh

# --- 6. FINALISE --- 
systemctl enable libvirtd.service virtlogd.service virtnetworkd.service virtstoraged.service virtnodedevd.socket piavpn.service sshd.service docker.service wolf-os-cleanup.service piavpn-tmpfiles.service

echo "✅ Sirius-OS Custom Assembly Complete!"

