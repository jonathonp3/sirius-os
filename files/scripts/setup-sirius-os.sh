#!/bin/bash
set -euo pipefail

echo "🚀 Starting Sirius-OS Master Assembly..." 

# --- 1. PRE-INSTALL IDENTITY ---
# Create groups if they don't exist (Bazzite likely has them already)
groupadd -r docker || true
groupadd -r libvirt-qemu || true
groupadd -r virtnetwork || true

# --- 2. AUTOMATED CLEANUP ---
echo "⚙️ Setting up First-Boot cleanup service..."
chmod +x /usr/libexec/sirius-os-firstboot.sh

# --- 3. FINALISE --- 
# This command fails the build if any of these files are missing from recipe.yml
systemctl enable \
    libvirtd.service \
    virtlogd.service \
    virtnetworkd.service \
    virtstoraged.service \
    virtnodedevd.socket \
    sshd.service \
    docker.service \
    sirius-os-cleanup.service \
    app-tmpfiles.service

echo "✅ Sirius-OS Custom Assembly Complete!"

