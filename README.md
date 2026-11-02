# Jexactyl Auto Installer

One-shot installer for **Jexactyl Panel + Wings Node** on Ubuntu / Debian.
Give it your panel domain and node domain, and it installs everything until the node turns **green** and is ready to use.

Made by **ZeroTzyID** · [github.com/zerotzyid](https://github.com/zerotzyid)

---

## Features

- Full install: Panel + Node on one server in a single run
- Modern TUI: arrow-key menu, progress bar, spinner, install plan, final summary card
- Reads the PHP version the panel release requires and installs exactly that (currently PHP 8.4), then makes it the default `php`
- Automatic SSL (Let's Encrypt) for the panel and every node
- Node is created, configured and verified automatically (waits until the panel sees Wings online)
- Add remote nodes over SSH (password or key)
- Register a node to an existing panel using an Application API key
- Bot mode for Telegram bots / scripts: no terminal, no prompts, JSON status and result
- Readable error report with a ready-to-copy text block when something fails
- Extras: upgrade Panel, upgrade Wings, phpMyAdmin, emergency MariaDB / database host reset

## Requirements

- Fresh server, run as `root`
- Ubuntu 20.04 / 22.04 / 24.04 or Debian 11 / 12 (x86_64 or arm64), systemd
- DNS **A records** for the panel and node domain pointing to the server IP
  (Cloudflare: **DNS only**, grey cloud)
- Ports `80`, `443`, `8080`, `2022` open, plus your allocation port range

## Quick start (interactive)

```bash
bash <(curl -s https://raw.githubusercontent.com/zerotzyid/Jexactyl-auto-installer/refs/heads/main/install.sh)
```

Choose **1 - Full install**, then enter your own:

- Panel FQDN
- Admin email (e.g. your Gmail) and admin username
- Node FQDN and allocation port range

Nothing is filled in for you in interactive mode.

## Automatic mode

Add flags and the installer stops asking questions. Missing optional values use defaults
(email `admin@<domain>`, username `admin`, random password, ports `25565-25600`).

```bash
bash install.sh --full --panel panel.example.com --node node.example.com -y
```

With your own details:

```bash
bash <(curl -s https://raw.githubusercontent.com/zerotzyid/Jexactyl-auto-installer/refs/heads/main/install.sh) --full \
  --panel panel.example.com --node node.example.com \
  --email you@gmail.com --admin-user myadmin --ports 25565-25600 -y
```

## Bot mode (Telegram bot, scripts)

No terminal needed. This mode turns on automatically when there is no TTY.

```bash
nohup bash install.sh --auto --full \
  --panel panel.example.com --node node.example.com \
  --email you@gmail.com > /root/zt-install.out 2>&1 &
```

- Progress: `cat /var/log/zerotzyid-status.json`
- Result: the last line starting with `ZT_RESULT` (JSON with panel login and node status)
- Errors: lines starting with `ZT_ERROR|`

Example result:

```json
{
  "state": "done",
  "panel": { "url": "https://panel.example.com", "email": "you@gmail.com", "username": "admin", "password": "..." },
  "nodes": [ { "fqdn": "node.example.com", "id": "1", "status": "ok", "detail": "online" } ]
}
```

`state` is `running`, `done`, `done_with_errors` or `failed`.

## Options

| Option | Description |
| --- | --- |
| `--full` | Panel + Node on this server |
| `--panel-only` | Panel only |
| `--panel FQDN` | Panel domain |
| `--node FQDN` | Node domain |
| `--email EMAIL` | Admin email, also used for Let's Encrypt |
| `--admin-user NAME` | Admin username (default `admin`) |
| `--admin-pass PASS` | Admin password (default random) |
| `--ports RANGE` | Allocation ports (default `25565-25600`) |
| `--node-only` | Install Wings here and register to an existing panel |
| `--api-key KEY` | Application API key (`ptla_...`) for `--node-only` |
| `--remote SPEC` | Remote node over SSH, repeatable: `fqdn,host,port,user,password[,keyfile]` |
| `--auto`, `--bot` | No prompts, no colors, JSON status for bots |
| `--plain` | Machine-readable output (`ZT_PANEL`, `ZT_NODE`, `ZT_DONE`) |
| `--force` | Continue even if another panel exists on the server |
| `--dns-wait SEC` | How long to wait for DNS in auto mode (default 120) |
| `--harden` | Optional kernel hardening |
| `-y`, `--yes` | Accept defaults, no confirmation |
| `-h`, `--help` | Show help |

Remote node passwords must not contain a comma.

## Files

| Path | Purpose |
| --- | --- |
| `/var/log/zerotzyid-jexactyl.log` | Full install log |
| `/var/log/zerotzyid-status.json` | Live status for bots |
| `/root/jexactyl-credentials.txt` | Panel and database credentials |
| `/root/zerotzyid-error.txt` | Plain-text error report to copy and share |

## Troubleshooting

- **DNS check fails**: create the A record, set Cloudflare to DNS only, wait a minute, retry.
- **SSL fails**: port 80 must be free and reachable from the internet.
- **Node stays red**: allow ports `8080` and `2022` in the firewall and the provider security group.
- **Install fails**: copy the text printed under "Copy this text when asking for help".
- **Composer says PHP is too old**: run `update-alternatives --set php /usr/bin/php8.4`, then start the installer again.
- **Another panel already on the server**: use a clean server, or add `--force`.

## License

Copyright (c) 2026 ZeroTzyID. All rights reserved.
