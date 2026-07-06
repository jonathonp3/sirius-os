#!/bin/bash
set -euo pipefail

echo "🚀 Starting Serius-OS Master Assembly..."

# --- 1. PRE-INSTALL IDENTITY ---
# Create groups in the build factory
groupadd -r docker || true
groupadd -r libvirt-qemu || true
groupadd -r virtnetwork || true


# --- 7. AUTOMATED CLEANUP ---
echo "⚙️ Setting up First-Boot cleanup service..."

# Ensure clean up script is executable
chmod +x /usr/libexec/sirius-os-firstboot.sh

# --- 5. FINALISE --- 
systemctl enable libvirtd.service virtlogd.service virtnetworkd.service virtstoraged.service virtnodedevd.socket sshd.service docker.service sirius-os-cleanup.service app-tmpfiles.service

echo "✅ Sirius-OS Custom Assembly Complete!"
