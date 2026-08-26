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
| `10-bootstrap-not-circular.sh` | `FROM docker.io/library/archlinux:latest`, a digest rewritten to a tag | `not ok 1 - every base image is pinned by digest` |
| `20-no-swallowed-errors.sh` | `\|\| true` appended to the pacstrap line in the Dockerfile | `not ok 1 - no swallowed error at Dockerfile:41` |
| `20` | `continue-on-error: true` on a workflow step | `not ok 1 - no swallowed error at .github/workflows/ci.yml:41` |
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

## The workflow itself

| behaviour | fault injected | result |
| --- | --- | --- |
| a partial failure publishes nothing | `bootstrap/riscv64/etc/bootstrap-packages.txt` set to a package name that does not exist, on a throwaway branch | the riscv64 build fails at `Build and push by digest`, the other three still run because `fail-fast` is off, and the publish job never starts because it needs the whole matrix |

⚠ **What is still not proven this way.** The publish job's cross-registry copy to
Docker Hub cannot be exercised by a dry run, because a dry run pushes to one
registry by design. It is covered only by a real run.
