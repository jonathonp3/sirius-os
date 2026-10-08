# Sirius-OS

Sirius-OS is my personal OS image built from [Bazzite](https://github.com/ublue-os/bazzite/) with a full virtualization stack, including Docker.

## Components

- Fedora Silverblue (base)
- libvirt and virt-manager, with a working NAT bridge
  (via [`sirius-os-virtualization`](https://github.com/jonathonp3/sirius-os-virtualization))
- Private Internet Access VPN client
  (via [`sirius-os-pia-installer`](https://github.com/jonathonp3/sirius-os-pia-installer))
- Docker

The virtualization stack and the PIA installer are provided by the
[Sirius Provisioning Framework](https://github.com/jonathonp3/sirius-provisioning-framework)
(SPF). Wolf-OS uses SPF packages.

The PIA installer package contains only provisioning and automation
scripts. It does not include any Private Internet Access source code or
binaries. The PIA Linux application is fetched from the official PIA
website during the first-boot extraction phase and is prepared to run
natively on the Atomic system.

## License
See `LICENSE`.

## Installation

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
