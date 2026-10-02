# Linux System Status Script

`sysstatus.sh` is a read-only Bash script that reports CPU, memory, disk,
load average, uptime, top processes, network, and logged-in users.

## Usage

    ./sysstatus.sh          # readable report
    ./sysstatus.sh --json   # JSON for other tools

## Features

- Works without root and without a terminal (cron/systemd safe)
- Skips sections when a tool is missing (graceful degradation)
- Container detection and reboot-required check
- Never changes system state (idempotent)
- RFC 3339 timestamps

## Run it every 5 minutes with cron

    */5 * * * * /usr/local/bin/sysstatus --json > $HOME/sysstatus-latest.json 2>&1

Tested on Ubuntu (latest) in VirtualBox.
