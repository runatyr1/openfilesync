# OpenFileSync - User Guide

OpenFileSync is an open-source bidirectional file sync tool built on rclone bisync.
It syncs local directories with a remote storage backend (Hetzner Storage Box, any SFTP endpoint)
so you get Dropbox/Mega-like sync without vendor lock-in.

## Requirements

- **rclone** - installed by the installer if missing
- **inotify-tools** - for watch mode (auto file change detection)
- **systemd** - for scheduled/daemon sync services
- Linux (macOS support planned for later)

## Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/<user>/openfilesync/main/install.sh | bash

# Interactive setup (remote, mappings, ecosystems)
openfilesync init

# Preview what would sync
openfilesync sync --dry-run

# Run first sync (establishes baseline)
openfilesync sync

# Install systemd timer for automatic scheduled sync
openfilesync install-service
```

## Configuration

All config lives in `~/.config/openfilesync/`.

### Main Config (`openfilesync.conf`)

```ini
# rclone remote name (configured via rclone config)
REMOTE=hetznerbox

# Sync interval in seconds (for scheduled mode)
SYNC_INTERVAL=3600

# Watch mode: detect file changes and sync immediately
WATCH_ENABLED=false

# Conflict resolution: newer | older | larger | smaller
CONFLICT_RESOLVE=newer

# Max percentage of files allowed to delete in one run (safety net)
MAX_DELETE=10

# Log file location
LOG_FILE=/var/log/openfilesync.log
```

### Path Mappings (`mappings`)

Each device has its own local directory structure but shares a common remote layout.
The remote side is the canonical structure — all devices agree on remote paths,
but local paths can differ per machine.

Format: `remote_path = local_path`

**Device A** (`~/.config/openfilesync/mappings`):
```
home/1-projects             = /home/user1/syslab-nosync/1-projects
home/documents              = /home/user1/Documents
home/dotfiles/.bashrc       = /home/user1/.bashrc
home/dotfiles/.config/nvim  = /home/user1/.config/nvim
```

**Device B** (same remote paths, different local paths):
```
home/1-projects             = /home/user1/projects
home/documents              = /home/user1/Documents
home/dotfiles/.bashrc       = /home/user1/.bashrc
home/dotfiles/.config/nvim  = /home/user1/.config/nvim
```

Each mapping entry runs as a separate bisync operation. Filters apply relative
to each mapping, so exclusions like `node_modules/**` work correctly regardless
of where the directory lives locally.

**Tips:**
- Keep remote paths simple and flat (e.g. `home/projects`, `home/documents`)
- You can map individual files (like `.bashrc`) or entire directory trees
- Run `openfilesync sync --dry-run` after changing mappings to verify before syncing
- After adding or removing mappings, a `--resync` is required (the tool will prompt you)

### Ecosystem Filters (`ecosystems`)

Instead of manually writing exclusion rules, pick the ecosystems you work with.
OpenFileSync ships filter presets that get combined automatically.

```
# ~/.config/openfilesync/ecosystems
# One per line, available presets:
node
go
python
terraform
ansible
editor-vscodium
editor-vim
system
```

Each preset excludes the typical generated/cache directories for that stack
(e.g. `node_modules/**`, `.terraform/**`, `__pycache__/**`).

The `system` preset covers OS-level excludes: `.cache/**`, `.local/share/Trash/**`,
`.DS_Store`, swap files, etc. It's recommended for all users.

You can also add custom exclusions in `~/.config/openfilesync/filters.custom`:
```
- my-custom-dir/**
- *.sqlite
```

**After editing any filter file, a --resync is required on next run.**

## CLI Commands

| Command                       | Description                                      |
|-------------------------------|--------------------------------------------------|
| `openfilesync init`           | Interactive setup wizard                         |
| `openfilesync sync`           | Run sync once                                    |
| `openfilesync sync --dry-run` | Preview sync without making changes              |
| `openfilesync watch`          | Start file watcher (foreground)                  |
| `openfilesync status`         | Show last sync time, health, active mappings     |
| `openfilesync conflicts`      | List unresolved conflict files                   |
| `openfilesync install-service`| Install systemd units (timer and/or watcher)     |

## Sync Modes

### Scheduled (systemd timer)

Runs sync at a fixed interval (default: every hour). Good for large directories
where constant watching would be expensive. Set `SYNC_INTERVAL` in config.

### Watch (inotifywait)

Monitors included paths for file changes and triggers sync after a 10-second
debounce window. Gives near-realtime sync like Mega/Dropbox.

For large directory trees, you may need to increase the inotify watch limit:
```bash
echo "fs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/40-openfilesync.conf
sudo sysctl --system
```

### Both

Run the timer as a safety net alongside the watcher. The lock mechanism prevents
concurrent sync operations.

## Conflict Resolution

When the same file is modified on two devices between syncs, a conflict occurs.

With `CONFLICT_RESOLVE=newer` (default), the most recently modified version wins.
The losing version is saved as `filename.conflict1`, `filename.conflict2`, etc.
Nothing is lost.

Check for conflicts:
```bash
openfilesync conflicts
```

This scans all mapped local paths for `.conflict*` files and lists them.
You can then manually inspect and resolve (keep one, merge, etc.).

## Setting Up the rclone Remote

Before using OpenFileSync, configure your storage backend with rclone:

```bash
rclone config
```

For a Hetzner Storage Box:
- Type: `sftp`
- Host: `uXXXXXX.your-storagebox.de`
- Port: `23`
- User: `uXXXXXX`
- Auth: password or SSH key (key recommended for automation)

Test connectivity:
```bash
rclone ls hetznerbox:
```

## Safety Features

- **`--max-delete`**: Limits deletions to a percentage of total files (default 10%). Prevents catastrophic data loss from listing glitches.
- **`--resilient --recover`**: Auto-recovers from interrupted syncs without requiring manual `--resync`.
- **Lock file**: Prevents concurrent sync operations from colliding.
- **`--dry-run`**: Always available to preview before committing changes.
- **Conflict preservation**: Losing versions saved as `.conflict*` files, never silently overwritten.

## What NOT to Sync

Even with ecosystem filters, avoid syncing these through bidirectional sync:

- **`.git` directories** - contain lock files and packed objects sensitive to partial writes. Sync your working tree; use git itself for history.
- **Browser profiles** - databases and lock files break with sync conflicts.
- **`~/.ssh`** - different keys per machine is better security practice.
- **Runtime state** - PID files, sockets, D-Bus, PulseAudio config.
- **Package manager caches** - `~/.npm`, `~/.cache`, regenerable.

The `system` ecosystem filter handles most of these automatically.

## Logs

Sync logs go to the configured `LOG_FILE` (default `/var/log/openfilesync.log`).

When running as a systemd service, you can also use:
```bash
journalctl -u openfilesync-sync.service
journalctl -u openfilesync-watch.service
```

## Troubleshooting

- **"filters file has changed" error**: Run `openfilesync sync --resync` after editing filters or mappings.
- **Sync seems stuck**: Check for a stale lock file at `~/.local/share/openfilesync/lock`. The `--max-lock 2m` flag auto-expires locks older than 2 minutes.
- **Too many inotify watches**: Increase `fs.inotify.max_user_watches` (see Watch mode section).
- **Slow first sync**: Expected for large datasets (800GB+). Let the initial `--resync` complete uninterrupted.
