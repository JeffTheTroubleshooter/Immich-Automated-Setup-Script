# Immich Automated Setup Script

`immich-install.sh` installs [Immich](https://immich.app), the self-hosted photo and video server, using the official Docker Compose files. It installs Docker and Compose if needed, asks for a few settings, and starts the stack.

## What it does

- Detects your Linux distro and installs Docker and Docker Compose.
- Downloads Immich's official `docker-compose.yml` and `.env` into `/opt/immich` (default).
- Asks for custom values, such as the Postgres database password.
- Starts Immich and prints the URL.

## Supported distros

| Distro family | Status |
|---|---|
| Fedora | Tested, works |
| Debian, Ubuntu, Linux Mint, Pop!_OS, Zorin, elementary OS | Not tested, need feedback |
| RHEL, Rocky, AlmaLinux, CentOS, Oracle Linux | Not tested, need feedback |
| Arch, Manjaro, EndeavourOS, Garuda | Not tested, need feedback |
| openSUSE, SLES | Not tested, need feedback |
| Alpine | Not tested, need feedback |

If you try it on a distro marked "Not tested", please open an issue saying whether it worked.

## Install

```bash
bash immich-install.sh
```

Then open `http://<your-server-ip>:2283` and create your admin account.

For the database password, use letters and numbers only, and change it from the default `postgres`.

## Uninstall

```bash
bash immich-install.sh uninstall
```

This stops Immich and asks whether to remove its data too.

## Part of the Proxmox Homelab setup

This installer is used by [Proxmox-Homelab-Automated-Setup-Script](https://github.com/JeffTheTroubleshooter/Proxmox-Homelab-Automated-Setup-Script), which creates an LXC for each app on a Proxmox host and runs this script inside it.
