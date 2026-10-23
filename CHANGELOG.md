# SMB_Backup_tool stable changelog

## SMB Backup Tool 2.0.1 / KeenTool 2.0.6

- Correct tar exclusion paths when the backup source has `/` as its parent (including the default `/opt`). Previously an extra slash left exclusions absolute, while archive member names were relative; live logs/PCAP could enter the archive and fail backup creation.
- Normalize trailing slashes in source settings. Exclude `/opt/var/run` and `/opt/var/lock` alongside logs, temporary files and local backup staging. Exclude Unix sockets elsewhere in the source using a checked NUL-delimited inventory.
- Inspect the full 16-byte SQLite header after Base64 encoding; binary/non-SQLite `.db` files no longer inject NUL bytes into Bash command substitution. Retain coherent SQLite snapshots and verify their integrity.
- Keep strict archive error handling, remote read-back/checksum verification and retention only after successful verification. Do not stop services or ignore arbitrary tar failures. Configuration and scheduling are preserved.
- Add isolated archive regression coverage for root-parent/trailing-slash sources, volatile paths, real Unix sockets on CI, non-SQLite binary files and SQLite record preservation. Exercise GNU and BusyBox tar where available; NAS transport and router export are mocked.


Baseline: `48b1a83804c3dc9155b7eeb20f01c942c2f3e3c7`.

- Stable 2.0.0 uses the shared Entware Bash runtime, atomic job locks and maintenance deferral; selective uninstallation preserves configuration/data by default.
- Keep existing backup configuration, shares and schedules across package upgrades. Verify completed backup outcomes and expose verified backup state to Security & Health where available.
- Shared readable HTML/plain notifications and isolated checks for archive/transport failure behavior. No automatic credentials or new SMB backup jobs are introduced by suite installation.
