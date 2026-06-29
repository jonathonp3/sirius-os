# Sirius-OS

Sirius-OS is my personal OS image built from [Bazzite](https://github.com/ublue-os/bazzite/) with Private Internet Access (PIA) integrated into the image. It also includes a full virtualization stack, including Docker.

## Components
- [Bazzite](https://bazzite.gg/)
- [Private Internet Access (PIA)](https://www.privateinternetaccess.com)s
- Virtualization stack (Docker)

## License
See `LICENSE`.


## Installation

These instructions are for my family only. The image is designed to be read-only and is intended for personal use, so it isn’t set up for others to use or customise.

If you want to try my PIA integration on Silverblue, see:
https://github.com/jonathonp3/wolf-os

The first step is to rebase from Fedora Silverblue:

1. Rebase to the unsigned image:
```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/jonathonp3/sirius-os:latest
```

2. Reboot to complete the rebase:
```bash
systemctl reboot
```

3. Rebase to the signed image:
```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/jonathonp3/sirius-os:latest
```

4. Reboot again to complete the installation
```bash
systemctl reboot
```

5. Upgrade to the latest build
```bash
rpm-ostree upgrade
```

6. Check status
```bash
rpm-ostree status
```

## How to build an ISO

1. Create the installer runtime:

```bash
podman run --pull always --rm ghcr.io/blue-build/cli:latest-installer | bash
```

2. Generate the ISO from the repository image:
```bash
sudo bluebuild generate-iso --iso-name zeta-os.iso image ghcr.io/jonathonp3/sirius-os:latest
```

## How to revert back to the stock Bazzite image:

1. Rebase to unsigned official Bazzite image:
```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/ublue-os/bazzite-gnome:stable
sudo systemctl reboot
```

2. Rebase to signed official Bazzite image
```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-gnome:stable
sudo systemctl reboot
```
