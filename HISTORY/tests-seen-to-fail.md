# Every test, and the fault that makes it fail

⭐ **A test that has never been seen to fail is not known to work.** A test can
pass because the thing it guards is healthy, or because it asserts nothing. The
two look identical in a green run.

Each row below records a fault that was injected into a scratch copy of the
tree, and the assertion that caught it. Measured 2026-08-26. Nothing here was
injected into the repository itself.

Re-run any of these by copying the tree to a scratch directory, applying the
fault, and pointing `REPO_ROOT` at that directory.

## Static suite

| test | fault injected | caught by |
| --- | --- | --- |
| `00-workflow-branch-buildable.sh` | the pre-change workflow, which hand-cloned the default branch | `not ok 1 - actions/checkout is used`, `not ok 2 - the workflow does not hand-clone the repository`, `not ok 3 - build context is the workspace` |
| `00` | `actions/checkout@v7.0.1`, a pin rewritten back to a tag | `not ok 1 - actions/checkout is pinned to a commit hash` |
| `05-harness.sh` | `not_ok` stops incrementing `TESTS_FAILED`, so a suite with a failing assertion exits 0 | `not ok 5 - summary returns 1 when one assertion failed` |
| `05` | `ok` stops incrementing `TESTS_RUN` | `not ok 1`, `not ok 2`, `not ok 4`, `not ok 5`, showing `ok 0 - first` and a plan of `1..0` |
| `05` | `summary` returns 0 instead of 1 | `not ok 5`, `not ok 6 - summary returns 1 when nothing ran at all` |
| `05` | `grep_matches` returns 0 instead of 2 on a file it cannot read | `not ok 9 - grep_matches returns 2 when the file cannot be read` |
| `05` | `fail` stops calling `diag`, so an assertion fails with no reason printed | `not ok 3 - fail prints its diagnostics as TAP comments` |
| `10-bootstrap-not-circular.sh` | `FROM docker.io/library/archlinux:latest`, a digest rewritten to a tag | `not ok 1 - every base image is pinned by digest` |
| `20-no-swallowed-errors.sh` | `\|\| true` appended to the pacstrap line in the Dockerfile | `not ok 1 - no swallowed error at Dockerfile:41` |
| `20` | `continue-on-error: true` on a workflow step | `not ok 1 - no swallowed error at .github/workflows/ci.yml:41` |
| `25-pipeline-traps.sh` | `\| head -n "$LIMIT"` in a script that sets pipefail | `not ok 1 - none of the N pipefail scripts uses a pipeline that fails on a normal result`, naming `scripts/faulty:3` |
| `25` | the `grep -c` form restored at `scripts/gen-mirrorlist:278` | `not ok 1`, naming the file and line |
| `25` | the `grep -c` form restored at `.github/workflows/freshness-mirrors.yml:47` | `not ok 2 - none of the 5 workflows uses a pipeline that fails on a normal result` |
| `30-signature-checking-on.sh` | `SigLevel = Never` in `rootfs/riscv64/etc/pacman.conf` | `not ok 7 - does not disable signature checking`, `not ok 8 - sets SigLevel = Required` |
| `40-mirrors-reachable.sh` | the riscv64 list cut to one server, which is the shape that caused the outage | `not ok 11 - offers a fallback server`, `not ok 16 - keeps at least 2 reachable servers` |
| `40` | ten of thirteen amd64 servers replaced with unresolvable hosts | `not ok 13 - keeps at least 7 reachable servers` |
| `50-supply-chain.sh` | `actions/checkout@v7.0.1` at all three call sites | `not ok 1..3 - action is pinned to a commit hash at ...` |
| `60-tag-families.sh` | `riscv64` given `amd64` as a second alias | `not ok 4 - riscv64 has 1 alias name(s)`, `not ok 22 - no alias is claimed by two architectures` |
| `60` | `emit` stopped after the first registry, so only one organisation name is used | `not ok 5 - amd64 emits 12 tags` and 14 others, `# failed 15 of 24` |
| `70-executable-bits.sh` | `git update-index --chmod=-x scripts/tag-names` | `not ok 1 - every invoked file is executable in the index` |
| `70` | a test file present on disk but not added to git | `not ok 2 - every invoked file is tracked by git` |
| `80-docs-claims.sh` | the usage block the README shipped before, where `!#` is not a comment | `not ok 2 - README.md bash block 9 parses` |
| `80` | the badge pointed back at `github.com/pkgforge/docker-archlinux` | `not ok 3 - README does not link to github.com/pkgforge/docker-archlinux` |
| `80` | every mention of GHCR removed from the README | `not ok 4 - README names the publish target ghcr.io/pkgforge-dev/archlinux` |
| `80` | a tag name documented that `tag-names` never emits | `not ok 6 - documented but never created: rv64gc` |
| `80` | a tag name emitted that the README does not document | `not ok 7 - created but undocumented: armv7` |
| `80` | an example with a shell syntax error | `not ok 1 - examples/99-broken.sh parses as bash` |
| `80` | `examples/` deleted | `not ok 1 - examples/ exists` |
| `80` | `set -euo pipefail` restored above a pipeline piping into `head` | `not ok 2 - no example sets pipefail alongside a pipeline that exits early` |

## Image suite

Fixtures were built for these rather than modifying a real image.

| test | fault injected | caught by |
| --- | --- | --- |
| `10-shell-present.sh` | `FROM scratch` with one file, which is the state the published riscv64 image was in | `not ok 1 - /bin/sh exists and resolves`, `not ok 2 - /usr/bin/bash exists and resolves` |
| `20-os-release.sh` | `/etc/os-release` and `/usr/lib/os-release` removed | `not ok 1 - /etc/os-release exists` |
| `30-ca-bundle.sh` | `/etc/ssl/certs/ca-certificates.crt` removed | `not ok 1 - resolves in ...` |
| `30` | the published `riscv64` image, unmodified | `not ok 1 - resolves`, and the published `amd64` image passes with 121 certificates, so the test discriminates rather than always failing |
| `40-evidence.sh` | a `sha256` set to null on one entry | `not ok 13 - incomplete entries: audit` |
| `40` | a `sha256` that is not 64 hex characters | `not ok 13` |
| `40` | a package `size` of zero | `not ok 13` |
| `40` | a `released` date of `-`, the value written when upstream publishes none | `not ok 13` |
| `40` | `platform` changed to another architecture | `not ok 9 - evidence platform matches the image under test` |
| `40` | `digest` changed to zeroes | `not ok 10 - evidence digest matches the image` |
| `40` | `source_commit` truncated to a short hash | `not ok 11 - evidence source_commit is a full commit hash` |
| `40` | `anchor.version` set to a version no package carries | `not ok 14 - the anchor appears in the recorded packages` |
| `40` | `packages` emptied | `not ok 12 - evidence records at least one package` |
| `40` | a top level key deleted | `not ok 5 - evidence has a top level built` |
| `50-consumer-contract.sh` | `LocalFileSigLevel` moved above the global `SigLevel` | `not ok 2 - the first SigLevel line in /etc/pacman.conf is the global one` |
| `50` | every `SigLevel` line deleted | `not ok 2 - /etc/pacman.conf carries a SigLevel line`, `not ok 3 - SigLevel is Required in the shipped /etc/pacman.conf` |
| `50` | a commented `#[multilib]` block appended to `/etc/pacman.conf` | `not ok 4 - /etc/pacman.conf carries no multilib block` |
| `50` | `/etc/pacman.d/gnupg/pubring.gpg` truncated to zero bytes | `not ok 5 - the pacman keyring is populated` |
| `50` | `/usr/bin/locale-gen` removed | `not ok 6 - locale-gen is present` |
| `50` | `/usr/share/i18n/charmaps/UTF-8.gz` removed, the file the `!` re-include lines keep | `not ok 7 - the UTF-8 charmap survives NoExtract` |
| `50` | root's password field emptied to `root::`, the CVE-2019-5021 shape | `not ok 8 - root has no empty password field in /etc/shadow` |

The two fixtures for `50` are `.tmp/phased/Containerfile.faultA`, which carries
six faults at once, and `.tmp/phased/Containerfile.faultB`, which deletes every
`SigLevel` line to reach the two branches fault A cannot. All 8 assertions pass
against the published image and 6 then 2 of them fail against the fixtures:

```bash
podman build --platform linux/amd64 -f .tmp/phased/Containerfile.faultA -t localhost/faulta:test .tmp/phased
REPO_ROOT="$(pwd)" IMAGE=localhost/faulta:test PLATFORM=linux/amd64 bash tests/image/50-consumer-contract.sh
```

## The workflow itself

| behaviour | fault injected | result |
| --- | --- | --- |
| a partial failure publishes nothing | `bootstrap/riscv64/etc/bootstrap-packages.txt` set to a package name that does not exist, on a throwaway branch | the riscv64 build fails at `Build and push by digest`, the other three still run because `fail-fast` is off, and the publish job never starts because it needs the whole matrix |

⚠ **What is still not proven this way.** The publish job's cross-registry copy to
Docker Hub cannot be exercised by a dry run, because a dry run pushes to one
registry by design. It is covered only by a real run.
