# SMB_Backup_tool stable changelog

Baseline: `48b1a83804c3dc9155b7eeb20f01c942c2f3e3c7`.

- Stable 2.0.0 uses the shared Entware Bash runtime, atomic job locks and maintenance deferral; selective uninstallation preserves configuration/data by default.
- Keep existing backup configuration, shares and schedules across package upgrades. Verify completed backup outcomes and expose verified backup state to Security & Health where available.
- Shared readable HTML/plain notifications and isolated checks for archive/transport failure behavior. No automatic credentials or new SMB backup jobs are introduced by suite installation.
