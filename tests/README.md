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
| `10-bootstrap-not-circular.sh` | no `FROM` names an image this repository publishes, and every non-scratch base is pinned by digest |
| `20-no-swallowed-errors.sh` | no `continue-on-error`, `\|\| true`, `set +e` or `2>/dev/null` in the workflows, the Dockerfile or `scripts/`, outside `tests/policy/swallowed-errors.allow` |
| `30-signature-checking-on.sh` | every shipped `pacman.conf` sets `SigLevel = Required` and none sets any SigLevel to `Never` |
| `40-mirrors-reachable.sh` | each list carries a generation date and is within the age bound, ships a fallback server and at least one over https, and keeps at least two reachable servers and at least half of what it ships. Every entry that does not answer 200 is named as a diagnostic |
| `50-supply-chain.sh` | every action is pinned to a commit hash and names its version, nothing pipes a remote script into a shell, no opaque binary is fetched and made executable, no deprecated workflow command, every workflow declares least-privilege `permissions` |
| `60-tag-families.sh` | `scripts/tag-names` emits every alias for each architecture on both registry names, each with a rolling, a dated and a pinned shape, plus the `latest` and `v<version>` index tags, with no alias claimed twice and an unknown architecture or empty version refused |
| `70-executable-bits.sh` | every file the workflows and the Dockerfile invoke as a command is tracked and mode `100755` **in the git index**, which is what CI checks out |
| `80-docs-claims.sh` | every `examples/*.sh` and every fenced `bash` block in the three README files parses, the README links to the repository that exists and names both publish targets, the documented tag names and the ones `scripts/tag-names` emits are the same set, and every path the README says is not extracted has a `NoExtract` rule |
| `90-package-lists.sh` | every `bootstrap/<arch>/etc/bootstrap-packages.txt` holds only package names, one list exists per matrix architecture, and the two ARM ports name `archlinuxarm-keyring`. xargs has no comment syntax, so a `#` line becomes a package named `#` |

## Image suite

| test | asserts |
| --- | --- |
| `10-shell-present.sh` | `/bin/sh` and `/usr/bin/bash` exist and resolve |
| `20-os-release.sh` | `/etc/os-release` exists and carries `ID` and `VERSION_ID`, and `org.opencontainers.image.version` matches `VERSION_ID` |
| `30-ca-bundle.sh` | `/etc/ssl/certs/ca-certificates.crt` resolves and holds at least one certificate |
| `40-evidence.sh` | the evidence file names the image, platform, digest, build time, source commit and anchor, and every package entry carries a name, version, size, sha256 and release date |
| `50-consumer-contract.sh` | the shipped image still satisfies what the direct consumer patches: the first `SigLevel` line is the global one, `SigLevel` is `Required`, there is no multilib block, the keyring is populated, `locale-gen` and the UTF-8 charmap survive `NoExtract`, and root has no empty password field |

Tests `10`, `20`, `30` and `50` create a container without starting it and copy
paths out. An image whose bootstrap installed nothing cannot execute anything, so a
test that ran a command inside it would fail with a runc error instead of a
readable assertion.

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
| `MIRRORLIST_PROBE_TIMEOUT` | `20` | `40-mirrors-reachable.sh` |
| `MIRRORLIST_PROBE_RETRIES` | `2` | `40-mirrors-reachable.sh` |
| `CA_BUNDLE_MIN_CERTS` | `1` | `30-ca-bundle.sh` |

`40-mirrors-reachable.sh` needs network. It retries before calling a mirror
dead, because a single probe against every entry produces occasional false
failures.
