#!/bin/bash
set -euo pipefail

echo "🚀 Starting Sirius-OS Master Assembly..." 

# --- 1. PRE-INSTALL IDENTITY ---
# Create groups if they don't exist
groupadd -r docker || true

# --- 2. AUTOMATED CLEANUP ---
echo "⚙️ Setting up First-Boot Optimization service..."
chmod +x /usr/libexec/sirius-os-optimization.sh
chmod +x /usr/libexec/sirius-os-provision.sh

# --- 3. ENABLE SYSTEMD UNITS IN THE VENDOR LAYER ---
mkdir -p /usr/lib/systemd/system/multi-user.target.wants

ln -sf ../sirius-os-provision.service \
    /usr/lib/systemd/system/multi-user.target.wants/sirius-os-provision.service

echo "✅ Sirius-OS Custom Assembly Complete!"

