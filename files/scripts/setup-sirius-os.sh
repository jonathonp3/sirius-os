#!/bin/bash
set -euo pipefail

echo "🚀 Starting Sirius-OS Master Assembly..." 

# --- 1. PRE-INSTALL IDENTITY ---
# Create groups if they don't exist
groupadd -r docker || true

# --- 2. AUTOMATED CLEANUP ---
echo "⚙️ Setting up First-Boot Optimization service..."
chmod +x /usr/libexec/sirius-os-firstboot.sh

# --- 3. FINALISE --- 
# This command fails the build if any of these files are missing from recipe.yml
systemctl enable \
    sshd.service \
    docker.service \
    sirius-os-optimization.service

echo "✅ Sirius-OS Custom Assembly Complete!"

