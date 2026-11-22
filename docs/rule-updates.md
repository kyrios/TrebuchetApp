# Version-bound rules and a future update channel (design, not built)

Status: design note, 22.11.2026. Nothing here downloads anything yet.

## The problem
Some fixes are tied to one version of something we do not control:
- **grade D**: a game build (the health-bar speed-up, the planned stack-cookie rule T13),
- **grade C**: a macOS/Rosetta build (the stutter fix F54a).

Each one already finds its sites by **fingerprint**, not by fixed offsets, and switches itself off on any version it does not recognise (fail-closed). After a game or macOS update, re-deriving a rule is usually a new fingerprint or pattern, not new code. Today that still means a new release download.

## What the launcher does now (built)
1. `rules.manifest` (installed next to `run-aoe2.sh`) lists every version-bound rule: id, grade, target (`game` or `rosetta`), the player-facing name, its off switch, where its status comes from and where its pattern lives (`builtin:` = inside a shipped file today).
2. When a rule switches itself off because the version does not match, the launcher **says so**: one notification per rule ("Stutter fix is off: it does not match this macOS/Rosetta version. The game runs normally; the other fixes stay on.") and a line in `logs/reports-*.log`. The other fixes stay on.
3. The CrossOver gate (`MANIFEST`) is unchanged: on any CrossOver mismatch everything is off and the game starts the normal way, with a notification.
4. `rules.manifest` is hashed into the installed `MANIFEST`, so a changed file is noticed like any other file.

## The later update channel (design)
**Goal:** after a game patch, players get re-derived patterns within hours, without downloading new binaries.

- **Pattern pack.** Rule patterns move out of the binaries into data files next to `rules.manifest` (`pattern=file:rules/t13.json`, `pattern=file:rules/reorder.json`). The sidecar and `mk_reorder.py` read them; the code that applies a pattern stays in the signed binaries. A pack is `rules.manifest` + its pattern files, with `pack <version> format=<n>`.
- **What a pack may contain.** Only data the shipped code already understands: byte patterns, fingerprints, offsets relative to a matched pattern, expected game or Rosetta build hashes. Never code. A pack whose `format` is newer than the launcher's is ignored.
- **Distribution.** A static file on the project's GitHub Releases (or Pages): `rules-pack-<version>.tar` + a detached signature. The launcher checks at most once a day, in the background, and never blocks the game start.
- **Trust.** Packs are signed with the project's key (minisign or ed25519). The public key ships with the release. The launcher installs a pack only if the signature verifies and every pattern file's hash matches the pack's own list. This replaces the plain `MANIFEST` hash line for `rules.manifest`: the gate then trusts "signed by the project key", not "this exact file".
- **Safety.** A new pack can only turn a rule on where its fingerprints match exactly; anything else stays fail-closed, with the same warning. Rolling back = deleting the pack folder (the release's own pack is the fallback).
- **Multiplayer.** A pack that changes a translation rule counts as a new rule version: it must pass the same replay checksum gate (offline, full replays) before it is published.
- **Player control.** An off switch for updates (`AOE2_NO_RULE_UPDATES=1`), and the notification names the pack version in use.

## Not decided
Key custody, hosting, the check interval and whether updates are opt-in are the maintainer's decisions.
