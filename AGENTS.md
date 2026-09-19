# TierNest project instructions

## Release and upgrade policy (user decision, 2026-09-12)

- Publish one universal arm64 module ZIP for each version. Use the same package for phones/tablets and Magisk, KernelSU, and APatch. Do not generate separate Mi10, MiPad, Ace3Pro, private, or device-bound releases.
- Keep the module ID `tiernest` stable so existing installations are upgraded in place by the root manager.
- Treat each installed device's configuration as authoritative. Preserve its TOML verbatim, command arguments, explicit routing strategy, hotspot preference, manual stop state, and existing backups. Back up the previous TOML and settings before migration.
- Merge supported existing runtime settings into new defaults; add missing new keys without resetting old choices. Retired device-profile revisions and host/IP mismatches must never trigger a configuration replacement.
- Never embed a user's network secret, hostname, peers, or device IP in the universal ZIP. First installation uses an unconfigured template; upgrades inherit local configuration.
- Use `scripts/build-module.sh` as the release entry point and `module/module.prop` as the version source. Former private/device build scripts only redirect no-argument callers to the universal build and reject private arguments.
- Run migration regressions for all three former package labels, first install, legacy EasyTier migration, routing preservation, backups and failed migrations. Update `TierNest-故障与踩坑记录.md` for device issues and migration changes.
- Preserve the network snapshot variable-isolation fix. Confirmed code fixes and offline tests do not replace on-device upgrade/network/standby verification; report those limits accurately.
- Save user configuration backups in `/sdcard/Download/TierNest/backups/`. Automatically migrate the old internal backup tree (including upgrade snapshots) after shared storage is available, verify all bytes before deleting originals, and never overwrite existing Download files. Do not add standby polling for migration.
- Offer manual and automatic service modes. Explicit stop terminates the core and every module worker, clears module routes, persists across reboot, and overrides automatic mode. Automatic home standby may retain only its small home-network monitor. Preserve `service-mode.state` and `home-network.conf` across upgrades; never bundle a device's home identity.
- Automatic detection offers periodic HTTP verification (default 30 seconds, configurable) and Wi-Fi connection events (identity matching without recurring HTTP probes). Preserve `home-detection.conf` byte-for-byte across upgrades. Event-source failure must resume the core, respect manual stop and surface an error; never silently change the user's selected detection mode.

Earlier private-package/profile instructions in historical project notes describe old releases and do not apply to new releases.

## Repository privacy

- Use synthetic device names, network addresses, endpoints, locations and credentials in documentation and tests. Keep migration coverage for the former device labels without copying a user's network identity.
- Keep private packages, screenshots, raw diagnostic reports, configuration backups and runtime state outside the repository. Downloaded binaries, dependencies and release artifacts are ignored.
- The three tracked files in `module/config/` are public templates. Do not replace them with an installed device's configuration; use the installed WebUI or an external local configuration instead.
- Before committing, inspect the staged file list and content for private data. Use a non-personal author identity when preparing a shareable snapshot.
