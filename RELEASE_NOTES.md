# SMB_Backup_tool 2.0.0

Baseline: `48b1a83804c3dc9155b7eeb20f01c942c2f3e3c7`.

- Stable 2.0.0 uses the shared Entware Bash runtime, atomic job locks and maintenance deferral; selective uninstallation preserves configuration/data by default.
- Keep existing backup configuration, shares and schedules across package upgrades. Verify completed backup outcomes and expose verified backup state to Security & Health where available.
- Shared readable HTML/plain notifications and isolated checks for archive/transport failure behavior. No automatic credentials or new SMB backup jobs are introduced by suite installation.

## Installation and compatibility

Install/update through the complete KeenTool 2.0.0 suite asset. Component archives require the coordinated shared runtime; do not replace isolated scripts over older installations. Existing settings, credentials, databases and upgrade schedules are preserved. Read the suite docs/INSTALL.md and SECURITY.md.

## Known feed limitation

IPdeny IPv6 KP may return HTTP 404; incomplete candidates retain the installed GeoBlock6 list. Cached installation time is not source freshness. This is reported explicitly, not silently bypassed.

## Validation

See suite docs/VALIDATION.md for isolated regression results and the live-router acceptance steps that remain before publication. This prepared release is a draft; no router reboot or public deployment is claimed.
