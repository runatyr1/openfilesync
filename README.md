# OpenFileSync

Bidirectional file sync over SFTP, powered by [rclone bisync](https://rclone.org/bisync/).

Sync your files across devices using cheap SFTP storage (Hetzner Storage Box, etc.) instead of proprietary cloud sync services.

## Install

```bash
curl -fsSL https://get.openfilesync.runatyr.dev/ | bash
```

This installs rclone (if missing), inotify-tools, and the `ofs` binary.

Then run the setup wizard:

```bash
ofs init
```

The wizard will ask you:
1. SFTP host, port, username, and auth method (password or SSH key)
2. Which local folders to sync (enter paths one by one)
3. Confirm a dry-run preview, then run the initial sync
4. Optionally install a systemd timer for automatic sync every 30 min

Config is saved to `~/.config/openfilesync/`. Remote paths mirror your local structure by default (e.g. `~/Documents` → `Documents` on the remote).

## Usage

```bash
ofs sync              # Run sync once
ofs sync --dry-run    # Preview changes
ofs status            # Check sync health
ofs conflicts         # List conflict files
ofs log               # Tail sync log
```

## What it does

- Syncs selected folders bidirectionally between your machine and an SFTP remote
- Built-in filter presets for Node.js, Go, Python, Terraform, Ansible, VSCodium, Vim
- Excludes `.git`, `node_modules`, build dirs, caches automatically
- Conflicts resolved by keeping the newest file (older saved as `.conflict`)
- Scheduled via systemd timer (every 30 min by default)
- Logs to `~/.local/share/openfilesync/openfilesync.log` (auto-trimmed to 15 days)

## License

MIT
