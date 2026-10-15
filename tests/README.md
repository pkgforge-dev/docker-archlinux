# Tests

Two suites. The static suite reads the repository and needs no container
runtime. The image suite inspects a built image.

```bash
tests/run.sh static
IMAGE=ghcr.io/pkgforge-dev/archlinux:latest PLATFORM=linux/riscv64 tests/run.sh image
tests/run.sh all
```

Output is TAP. A failing assertion prints the measurement and a command that
reproduces it. Exit status is non-zero when any assertion fails.

## Static suite

| test | asserts |
| --- | --- |
| `00-workflow-branch-buildable.sh` | the workflow builds the triggering ref, through `actions/checkout` pinned to a commit hash, with no hand-clone |
| `05-harness.sh` | `lib/harness.sh` itself: `ok` and `fail` number and count, `summary` returns non-zero when anything failed and when nothing ran, `grep_matches` tells no-match from cannot-read, `image_digest` reads a digest already in the reference. ⛔ It reports through its own counters, never the harness, because a reporter checked through itself cannot fail when the reporter is what is broken |
| `10-bootstrap-not-circular.sh` | no `FROM` names an image this repository publishes, and every non-scratch base is pinned by digest |
| `15-actionable-failures.sh` | every `fail` call in `tests/` carries a line starting `reproduce:`. A test that prints only what it expected leaves the reader to rebuild the command from the source |
| `20-no-swallowed-errors.sh` | no `continue-on-error`, `\|\| true`, `set +e` or `2>/dev/null` in the workflows, the Dockerfile or `scripts/`, outside `tests/policy/swallowed-errors.allow` |
| `25-pipeline-traps.sh` | no script that sets `pipefail`, and no workflow `run` block, pipes into `head` or counts with a `grep` count flag. Both fail on a result that is normal, and both stop the script with no message |
| `30-signature-checking-on.sh` | every shipped `pacman.conf` sets `SigLevel = Required` and none sets any SigLevel to `Never` |
| `35-publish-targets.sh` | a dry run cannot reach a real repository: each scratch name differs from its real counterpart, no tag-creating step names `GHCR_IMAGE` or `HUB_IMAGE` directly, `dry_run_hub` is refused without `dry_run`, and the publish job verifies the index on both registries. It also asserts the rollback guard: the workflow calls `scripts/check-anchor-floor`, `allow_anchor_downgrade` is an input, and the override is not switched on in the workflow itself |
| `40-mirrors-reachable.sh` | each list carries a generation date, ships a fallback server and at least one over https, and is measured for its age and for how many of its servers answer. The age bound and the reachable floor, at least two and at least half of what it ships, fail only with `MIRRORLIST_STRICT=1`, because both measure the world rather than the tree and either one closing the gate stopped every build. Every entry that does not answer 200 is named as a diagnostic. Each list also starts with the servers of `mirrors/<arch>.anchors`, in their order, which is the order pacman and `scripts/check-mirror-lag` read |
| `45-pacman-conf-shape.sh` | the shipped `pacman.conf` files agree: the same `[options]` directives apart from `Architecture`, one named architecture each and no two the same, both `DisableSandbox` directives present and commented, and `DownloadUser` unset. The last two are recorded choices, explained in the configs and measured in `HISTORY/defect-parity.md` |
| `50-supply-chain.sh` | every action is pinned to a commit hash and names its version, nothing pipes a remote script into a shell, no opaque binary is fetched and made executable, no deprecated workflow command, every workflow declares least-privilege `permissions` |
| `55-shipped-hooks.sh` | every hook this repository ships into the image declares the five directives alpm requires, carries both section headers, runs Pre or PostTransaction, declares `Depends`, and runs no `/usr/local` path that is not also shipped. ⛔ A hook alpm cannot parse, or whose `Exec` is missing, aborts every transaction the consumer runs |
| `60-tag-families.sh` | `scripts/tag-names` emits every alias for each architecture on both registry names, each with a rolling, a dated and a pinned shape, plus the `latest` and `v<version>` index tags, with no alias claimed twice and an unknown architecture or empty version refused |
| `65-fetch-policy.sh` | every fetch in `scripts/`, the workflows and `bootstrap/any` sets `--connect-timeout` and `--max-time`. curl's default connect timeout is around two minutes and it has no default total timeout, so a mirror that connects and then stalls holds the job until CI kills it. A curl written inside a diagnostic is skipped |
| `66-mirror-lag.sh` | a first server that is behind upstream is not what the build reads. `scripts/check-mirror-lag` keeps a first server that is as current as the next one, one hour behind, or ahead, and drops one that is two days behind, one that serves no database where the next one does, and one that is current for `core` and behind for `extra`. It steps over an error page to find the reference, keeps the first server when nothing after it answers, reads `MIRROR_LAG_MAX`, and does not judge a section that reads another list. `drop-server` removes one exact `Server` value and keeps the rest, and refuses a value that is absent, a prefix of a line, or the last server. `scripts/resolve-anchor` passes over `SKIP_SERVER`. The wiring is read: the `Dockerfile` drops the server before `pacstrap`, every build step passes `SKIP_SERVER`, and the resolve job checks before it resolves. The mirrors are local files |
| `67-mangled-responses.sh` | `scripts/resolve-anchor` steps over a mirror that answers with the wrong thing and reaches the one that works: a zero byte database, a Zstandard shaped body that decompresses to nothing, an error page body, a truncated gzip, and a missing file. Every bad mirror is named and every complaint carries a reason. It then reads a database that really is Zstandard, from a repository named `base`, which is what three of the eight architectures need. ⚠ That half is skipped out loud on a host with no `zstd`. The mirrors are local files, because the image the static suite also runs in ships no python, no nc and no busybox |
| `68-evidence-snapshot.sh` | the evidence is resolved against the databases the build used: the `Dockerfile` exports them before it empties the directory, the export stage and step exist, and the build job passes `DB_SNAPSHOT`. ⚠ Whether the export hit the layer cache is not checkable from the tree. `HISTORY/evidence-race.md` |
| `69-evidence-damaged-database.sh` | `scripts/gen-evidence` reads a repository database that stores a desc member sparse, as Arch RISC-V's `extra.db` does, and accounts for every installed package around it. The damaged member is named, and an installed package whose own entry is damaged is refused as damaged upstream rather than blamed on the snapshot. The image read goes through a stand-in runtime, so no container and no network |
| `70-executable-bits.sh` | every file the workflows and the Dockerfile invoke as a command is tracked and mode `100755` **in the git index**, which is what CI checks out |
| `75-architecture-set.sh` | one architecture set, named the same way everywhere. The set is read from the build matrix, and every `for` loop over architecture names anywhere in the tree has to name all of it, whichever spelling it uses. Also `scripts/tag-names`, the `gen-mirrorlist` usage string, the per-architecture files, and the tag family assertions. ⛔ The sites are discovered, not listed: a test that named them by line would be one more place to edit when an architecture is added. A deliberate subset carries `arch-subset:` in the comment above it |
| `85-pacman-static-pin.sh` | every input to the static pacman is pinned by an https URL and a sha256 or by a full commit, zig is pinned for both host architectures the matrix can use, the pinned pacman commit is the one the published anchor family is named after, every matrix architecture has a target row in `scripts/build-pacman-static`, and neither the `Dockerfile` nor the bootstrap scripts name the binary. ⛔ Nothing here reaches the network: the anchor is a live value and a test that measured it would fail for a reason outside this repository |
| `80-docs-claims.sh` | every `examples/*.sh` and every fenced `bash` block in `README.md`, `examples/README.md`, `tests/README.md` and every file under `docs/` parses, the README links to the repository that exists and names both publish targets, the documented tag names and the ones `scripts/tag-names` emits are the same set, no shipped `pacman.conf` withholds any path, and the README says so |
| `88-keyring-pins-vendored.sh` | every keyring pin's package is carried in `bootstrap/keyrings/` under its own name, hashes to the pin, and trusts exactly the pinned fingerprints with the pinned expiry dates, and no package sits there that no pin names. The build reads the package from the tree, because a port deletes a superseded one from its mirror |
| `89-bot-merge-guard.sh` | `scripts/merge-bot-pr --check-diff` passes an action moved to a new commit hash with its version comment, and a base image moved to a new digest. It refuses a pin bump that carries another change, an action swapped for another repository's, hex that is not a whole hash or digest, and a pinned line added rather than moved, and reports an empty diff as nothing changed. The shapes are copied from Renovate pull requests |
| `90-package-lists.sh` | every `bootstrap/<arch>/etc/bootstrap-packages.txt` holds only package names, one list exists per matrix architecture, and the two ARM ports name `archlinuxarm-keyring`. xargs has no comment syntax, so a `#` line becomes a package named `#` |
| `95-publish-watchdog.sh` | the two checks that notice a schedule that stopped: the calendar and the cron reading against values worked out by hand, a cron that cannot be read is refused, every cron in the tree can be read, no threshold, year or list is written down, and the two workflows run the checks and gate nothing |
| `96-release-assets.sh` | the release publishes every asset family for every architecture or nothing, discovered from the build matrix, with the generators run against fixtures |
| `97-scratch-citations.sh` | nothing outside `HISTORY/` names a path in the gitignored scratch directory, and every `HISTORY/` document that names one carries the standing note that the path is not there |
| `98-text-encoding.sh` | no text file in the tree carries a character encoded twice, UTF-8 read as Latin-1 and written back. Three files under `mirrors/` carried eight such markers in comments that every reader skips |

## Image suite

| test | asserts |
| --- | --- |
| `10-shell-present.sh` | `/bin/sh` and `/usr/bin/bash` exist and resolve |
| `20-os-release.sh` | `/etc/os-release` exists and carries `ID` and `VERSION_ID`, and `org.opencontainers.image.version` matches `VERSION_ID` |
| `30-ca-bundle.sh` | `/etc/ssl/certs/ca-certificates.crt` resolves and holds at least one certificate |
| `40-evidence.sh` | the evidence file names the image, platform, digest, build time, source commit and anchor, and every package entry carries a name, version, size, sha256 and release date |
| `50-consumer-contract.sh` | the shipped image still satisfies what the direct consumer patches: the first `SigLevel` line is the global one, `SigLevel` is `Required`, there is no multilib block, the keyring is populated, `locale-gen` and the UTF-8 charmap are present, and root has no empty password field |
| `60-defect-parity.sh` | the failure modes on the upstream tracker, asked of this image: extended attributes and setuid bits survive packing, the merged `/usr` links hold, the alpm library initialises, `/etc/hosts` and `/etc/resolv.conf` are pacman backup files, a login shell is quiet, `/etc/machine-id` is present and empty, no private signing key is shipped, pacman-key's tools are on `PATH`, a locale outside the Latin alphabet generates and takes effect, and the linker this image ships puts a command installed outside `PATH` on it without shadowing anything. Each assertion names the issue it came from, and the measurements are in `HISTORY/defect-parity.md` |

Tests `10`, `20`, `30` and `50` create a container without starting it and copy
paths out. An image whose bootstrap installed nothing cannot execute anything, so a
test that ran a command inside it would fail with a runc error instead of a
readable assertion.

⚠ `60` is the exception and runs the image, because file modes, extended
attributes and locale generation are not observable through `cp` onto a host
with no notion of them, and a check that only worked on Linux would pass on
Windows for the wrong reason. It sends one probe over stdin, reads `key=value`
back, and reports a failed run as a single assertion carrying the runtime's own
words. `scripts/gen-evidence` runs the image for the same reason and runs before
it in CI.

### The evidence file

`40-evidence.sh` needs `EVIDENCE` pointing at the file for the image under test.
`scripts/gen-evidence` writes it:

```bash
SOURCE_COMMIT="$(git rev-parse HEAD)" BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  scripts/gen-evidence amd64 localhost/archlinux:amd64 linux/amd64 evidence-amd64.json
```

The installed set is read from the image's own pacman database. The size, the
checksum and the build date come from the repository databases, because the
local database carries no checksum. A value upstream does not publish is written
as a dash and `40-evidence.sh` names the entry, so an absent field is loud
rather than invented.

The build job runs this per architecture and uploads the result as an artifact.

## Settings

| variable | default | applies to |
| --- | --- | --- |
| `IMAGE` | none, required | image suite |
| `PLATFORM` | none, required | image suite |
| `EVIDENCE` | none, required | `40-evidence.sh` |
| `CONTAINER_RUNTIME` | `podman`, else `docker` | image suite |
| `MIRRORLIST_MAX_AGE_DAYS` | `90` | `40-mirrors-reachable.sh` |
| `MIRRORLIST_STRICT` | `0`. `1` fails on a stale list or one below its reachable floor | `40-mirrors-reachable.sh` |
| `MIRRORLIST_PROBE_TIMEOUT` | `20` | `40-mirrors-reachable.sh` |
| `MIRRORLIST_PROBE_RETRIES` | `2` | `40-mirrors-reachable.sh` |
| `MIRROR_LAG_MAX` | `43200`, seconds | `scripts/check-mirror-lag`, and `66-mirror-lag.sh` sets it for one case |
| `CA_BUNDLE_MIN_CERTS` | `1` | `30-ca-bundle.sh` |
| `DIRECTIVES_MIN` | `20` | `45-pacman-conf-shape.sh` |
| `SETUID_MIN` | `10` | `60-defect-parity.sh` |
| `PACKAGES_MIN` | `50` | `60-defect-parity.sh` |
| `PROFILE_SCRIPTS_MIN` | `1` | `60-defect-parity.sh` |
| `CHARMAPS_MIN` | `100` | `60-defect-parity.sh` |
| `LOCALE_SOURCES_MIN` | `300` | `60-defect-parity.sh` |

`40-mirrors-reachable.sh` needs network. It retries before calling a mirror
dead, because a single probe against every entry produces occasional false
failures.
