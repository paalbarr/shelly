# Shelly

A collection of standalone shell scripts for macOS/Linux system administration: cleaning up leftover software, monitoring disk space, benchmarking network throughput, and backing up/controlling VirtualBox virtual machines.

Each script is self-contained (no shared libraries) and documented in its own header comment. This README summarizes what each one does and how to run it.

## Contents

- [appcleanup.sh](#appcleanupsh)
- [diskalert.sh](#diskalertsh)
- [netmarks.sh](#netmarkssh)
- [vboxbackup.sh](#vboxbackupsh)
- [vboxcontrol.sh](#vboxcontrolsh)

---

## appcleanup.sh

**Platform:** macOS only

Finds — and optionally removes — leftover files from software that is no longer installed, similar to what AppCleaner/AppZapper do. It searches the usual macOS locations (`Application Support`, `Caches`, `Preferences`, `Containers`, `LaunchAgents`, `Application Scripts`, stray items directly under `~/Library`/`/Library`, and installer package receipts via `pkgutil`).

Two modes:

- **Name search** — target one specific product. Removes its leftovers by default (after a confirmation prompt).
- **`--scan`** — lists every application actually installed (by name and `CFBundleIdentifier`), then reports everything else as an orphan. Results are grouped by detected application (merging obvious name variants, e.g. `Familycircle`/`Familycircled`), sorted by size, largest first.

Nothing is permanently deleted by default — matches are moved to `~/.Trash` (user-level items) or a recoverable backup folder under `/private/tmp` (system-level items, via `sudo`). Pass `--force` to skip that and delete permanently instead.

### Usage

```bash
./appcleanup "name"              # remove that product's leftovers (asks to confirm)
./appcleanup "name" --details    # just show its references, don't remove
./appcleanup --scan              # scan and list ALL orphaned leftovers
./appcleanup --scan --deep       # also include unintelligible (UUID-named) items
./appcleanup --scan --remove     # scan and clean up what it finds
./appcleanup                     # show usage
```

### Options

| Option | Description |
|---|---|
| `-r`, `--remove` | Move matches to Trash/backup (`--scan` mode) |
| `-y`, `--yes` | Skip the confirmation prompt |
| `--include-app` | Also match the `.app` bundle in `/Applications` (name-search mode) |
| `--deep` | Include unintelligible/UUID-named items (`--scan` mode) |
| `--details` | Name-search: show references without removing. `--scan`: full path breakdown instead of the summary table |
| `--force` | Permanently delete instead of moving to Trash/backup — cannot be undone |
| `-h`, `--help` | Show usage |

---

## diskalert.sh

**Platform:** Linux/macOS (uses `df -H`)

Checks disk usage on a given path and logs the result. When usage reaches a configurable threshold, it runs a configurable action (e.g. a script that sends an email or hits a monitoring endpoint). Intended to run on a schedule (cron).

### Usage

```bash
./diskalert.sh
```

Configuration is done through environment variables (all optional, with sane defaults):

| Variable | Default | Description |
|---|---|---|
| `ALERT` | `25` | Usage percentage that triggers `ALERT_ACTION` |
| `WATCH_PATH` | `/home` | Filesystem path to check |
| `LOGFILE` | `logdisk.log` | Where each check is logged |
| `ALERT_ACTION` | `/usr/bin/php /your/script/in/php` | Command run when the threshold is reached |

```bash
ALERT=75 WATCH_PATH=/var LOGFILE=/var/log/diskalert.log ./diskalert.sh
```

---

## netmarks.sh

**Platform:** Linux/macOS

Runs an `iperf3`-based upload or download network benchmark against a host, plus a `ping`-based latency/packet-loss check, and prints a summary (transfer, bandwidth, latency, packets, loss) along with an ASCII bitrate chart.

Checks that every dependency is installed before doing anything, validates its arguments (rejects missing or non-numeric values for `-i`/`-t`), verifies each step (directory creation, `iperf3`, `ping`) actually produced output before parsing it, and computes packet loss in a way that works the same on Linux and macOS.

### Requirements

- `iperf3` (a reachable `iperf3` server must be running on the target host)
- `jq`
- `bc`
- `ping`
- `jp` (JSON terminal chart renderer, used to plot the bitrate chart)

### Usage

```bash
./netmarks.sh -h 192.168.1.10 -i 10 -t 4      # upload test
./netmarks.sh -h 192.168.1.10 -i 10 -t 4 -d   # download test
./netmarks.sh -m                              # show usage
```

### Options

| Option | Description |
|---|---|
| `-h`, `--host` | Target host (default `localhost`) |
| `-i`, `--intervals` | Test duration in seconds (default `1`) |
| `-t`, `--threads` | Number of parallel streams (default `1`) |
| `-d`, `--sequence` | Run a download test instead of upload |
| `-m`, `--man` | Show usage |

---

## vboxbackup.sh

**Platform:** Linux/macOS with VirtualBox installed

Backs up VirtualBox virtual machines: for each registered VM it gracefully shuts it down (ACPI, falling back to a forced power-off), exports it to an `.ovf`/`.vmdk` pair in a dated backup folder, and restarts it if it was running before the backup. Everything is logged, and a monitoring command can be run once the backup finishes.

### Requirements

`VBoxManage` and `VBoxHeadless` in `PATH`.

### Usage

```bash
./vboxbackup.sh
```

Configuration is done through environment variables:

| Variable | Default | Description |
|---|---|---|
| `LOGFILE` | `/the/path/for/log/file` | Log file for the run |
| `BACKUP_BASE` | `/the/path/for/backup/folder` | Base folder; a dated `VMs/` subfolder is created per run |
| `VM_FILTER` | *(empty = all VMs)* | Extended-regex (`grep -E`) filter on VM names |
| `MAX_RETRIES` | `3` | ACPI shutdown retry attempts |
| `SLEEP_TIME` | `15` | Seconds to wait between retries |
| `MONITOR_ACTION` | `/usr/bin/php /your/script/in/php` | Command run once the backup finishes |

```bash
BACKUP_BASE=/backups VM_FILTER="^prod-" ./vboxbackup.sh
```

---

## vboxcontrol.sh

**Platform:** Linux/macOS with VirtualBox installed

Simple front-end for starting/stopping VirtualBox VMs, either via one-shot commands or an interactive menu.

Checks that `VBoxManage`/`VBoxHeadless` are installed before starting, and parses VM names in a way that tolerates spaces. In `control` mode, a failed command (e.g. a typo'd VM name) is reported and returns you to the menu instead of ending the session.

### Usage

```bash
./vboxcontrol.sh start     # start all VMs
./vboxcontrol.sh stop      # stop all VMs
./vboxcontrol.sh restart   # stop then start all VMs
./vboxcontrol.sh control   # interactive menu (list/start/stop one or all VMs)
```

The interactive menu (`control`) lets you list all VMs, list only running VMs, and start or stop an individual VM by name.
