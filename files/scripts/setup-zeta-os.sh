#!/bin/bash
set -euo pipefail

echo "🚀 Starting Zeta-OS Master Assembly..."

# --- 1. PRE-INSTALL IDENTITY ---
# Create groups physically in the build factory so RPMs don't struggle
groupadd -r piavpn || true
groupadd -r piahnsd || true
groupadd -r docker || true

# Bake the blueprints for the kids' gaming pcs
mkdir -p /usr/lib/sysusers.d
cat <<EOF > /usr/lib/sysusers.d/zeta-os.conf
g piavpn - -
g piahnsd - -
g docker - -
# Add everyone to Docker and libvirt
m jonathon libvirt
m jonathon piavpn
m jonathon docker
m kyle libvirt
m kyle piavpn
m kyle docker
m james libvirt
m james piavpn
m james docker
m lucas libvirt
m lucas piavpn
m lucas docker
m nicholas libvirt
m nicholas piavpn
m nicholas docker
EOF

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


# --- 3. MASTER WIRING BLUEPRINT ---
mkdir -p /usr/lib/tmpfiles.d
cat <<EOF > /usr/lib/tmpfiles.d/piavpn.conf
d /var/lib/piavpn 0775 root piavpn -
d /var/run/piavpn 0775 root piavpn -
d /var/opt/piavpn 0755 root root -
d /var/opt/piavpn/etc 0775 root piavpn -
L /var/opt/piavpn/bin - - - - /usr/libexec/piavpn/opt/piavpn/bin
L /var/opt/piavpn/lib - - - - /usr/libexec/piavpn/opt/piavpn/lib
L /var/opt/piavpn/plugins - - - - /usr/libexec/piavpn/opt/piavpn/plugins
L /var/opt/piavpn/qml - - - - /usr/libexec/piavpn/opt/piavpn/qml
L /var/opt/piavpn/share - - - - /usr/libexec/piavpn/opt/piavpn/share
L /var/opt/piavpn/var - - - - /var/lib/piavpn
EOF

# --- 4. EXTRACTION ---
mkdir -p /usr/libexec/piavpn
# Note: In Zeta-OS recipe, we placed the tarball at /tmp/pia-backup.tar.xz
tar -xpJf /tmp/pia-backup.tar.xz -C /usr/libexec/piavpn/

# --- 5: SYSTEM INTEGRATION ---
mkdir -p /usr/lib/systemd/system /usr/lib/NetworkManager/conf.d /usr/share/applications /usr/share/pixmaps

cp /usr/libexec/piavpn/etc/systemd/system/piavpn.service /usr/lib/systemd/system/piavpn.service
cp /usr/libexec/piavpn/etc/NetworkManager/conf.d/wgpia.conf /usr/lib/NetworkManager/conf.d/wgpia.conf
cp /usr/libexec/piavpn/usr/share/applications/piavpn.desktop /usr/share/applications/piavpn.desktop
cp /usr/libexec/piavpn/usr/share/pixmaps/piavpn.png /usr/share/pixmaps/piavpn.png

# Path and Context fix
sed -i 's|ExecStart=.*|ExecStart=/opt/piavpn/bin/pia-daemon|' /usr/lib/systemd/system/piavpn.service
sed -i '/\[Service\]/a WorkingDirectory=/opt/piavpn' /usr/lib/systemd/system/piavpn.service

# --- 6. PERMISSIONS ----
setcap 'cap_net_bind_service=+ep' /usr/libexec/piavpn/opt/piavpn/bin/pia-unbound || true

# These will work now because we ran 'groupadd' in Step 1
chown root:piavpn /usr/libexec/piavpn/opt/piavpn/bin/pia-client
chown root:piavpn /usr/libexec/piavpn/opt/piavpn/bin/piactl
chmod 755 /usr/libexec/piavpn/opt/piavpn/bin/pia-client
chmod 755 /usr/libexec/piavpn/opt/piavpn/bin/piactl

# --- 7. NATIVE EDITOR INTEGRATION ---
# Remove the Flatpak version
flatpak uninstall --system -y org.gnome.TextEditor || true

# Set favourite as default
mkdir -p /usr/share/glib-2.0/schemas/
cat <<EOF > /usr/share/glib-2.0/schemas/99-wolf-os-editor.gschema.override
[org.gnome.TextEditor]
style-scheme='solarized-light-golden-sand'
EOF
glib-compile-schemas /usr/share/glib-2.0/schemas/

# --- 8. FINALIZE --- 
systemctl enable virtlogd.service piavpn.service docker.service

echo "✅ Zeta-OS Custom Assembly Complete!"

