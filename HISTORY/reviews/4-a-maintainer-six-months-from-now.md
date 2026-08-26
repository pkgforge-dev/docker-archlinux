# Review 4: a maintainer six months from now

**Lens.** Someone opening this repository cold. Can they state what every file is
for? Is every pin watched? Does every failure message say what to do?

**Date.** 2026-08-26. 69 tracked files at the time of review.

---

## Can every file's purpose be stated?

Measured by checking every tracked file for a header comment or self describing
prose:

```bash
git ls-files | while read -r f; do ... head -12 "$f" | grep -cE '^#|^//' ; done
```

Eight files had neither. Four are fixed, three were already adequate, one could
not be fixed and is now documented elsewhere.

| file | verdict |
| --- | --- |
| `bootstrap/any/usr/local/bin/pacstrap-docker` | ⛔ gap. Now carries a header saying what it does and why it is not upstream pacstrap |
| `rootfs/any/etc/locale.gen` | ⛔ gap. Now says what it generates and points at the example for adding a locale |
| `rootfs/any/etc/locale.conf` | ⛔ gap. Now says the image environment variables take precedence over it |
| `rootfs/any/etc/pacman.d/hooks/package-cleanup.hook` | adequate. Pacman hooks carry a `Description` field and this one uses it |
| `bootstrap/<arch>/etc/bootstrap-packages.txt`, four files | ⛔ **cannot carry a comment.** See below |

### The one that cannot be fixed in place

The Dockerfile runs `xargs -r -a /etc/bootstrap-packages.txt pacstrap-docker`.
xargs has no comment syntax. Measured:

```bash
printf '# a comment\nbase\n' | xargs -r echo
# a comment base
```

Three arguments, not one. pacman would fail with `target not found: #`, a long
way from the file that caused it. So the constraint is stated in the Dockerfile
beside the xargs call, and `tests/static/90-package-lists.sh` enforces it.

## Is every pin watched?

| pin | where | watcher |
| --- | --- | --- |
| 7 action commit hashes | `.github/workflows/*.yml` | Dependabot, `github-actions`, weekly. Guarded by three tests that fail on a tag |
| `docker.io/library/archlinux@sha256:` | `Dockerfile` | Dependabot `docker`, and `freshness-image-pins.yml` |
| `docker.io/koalaman/shellcheck@sha256:` | `.github/workflows/ci.yml` | ⛔ **was unwatched.** Dependabot's docker ecosystem reads Dockerfiles, not `docker run` in a workflow step. Now `freshness-image-pins.yml` |
| `docker.io/rhysd/actionlint@sha256:` | `.github/workflows/ci.yml` | same |
| ARM keyring package, sha256, master fingerprint | `bootstrap/keyrings/archlinuxarm.pin` | `freshness-keyring.yml`, weekly |
| mirror lists | `rootfs/*/etc/pacman.d/mirrorlist` | `freshness-mirrors.yml`, monthly |
| the riscv64 candidate pool | `mirrors/riscv64.pool` | probed and reported by `freshness-mirrors.yml`, hand maintained |
| the anchor package choice | `scripts/resolve-anchor` | the daily build itself. `resolve` dies if `pacman` stops existing on a port |

⭐ **The gap this review found was one I had introduced.** Adding two digest
pins to `ci.yml` created two pins with no watcher, in the same session that
wrote the policy about watching pins. It is now closed by
`scripts/check-image-pins`, which finds pins anywhere in the tree rather than
in a list someone has to remember to update.

## Does every failure message say what to do?

```bash
grep -cE '^[[:space:]]*(fail|die) ' tests/static/*.sh tests/image/*.sh scripts/*
grep -rhE 'reproduce:|fix with:|regenerate with:|resolve with:|Re-derive|usage:' ...
```

101 `fail` or `die` call sites. 39 lines carrying a `reproduce:`, `fix with:`,
`regenerate with:` or `usage:` instruction.

⚠ **That ratio is honest, not good.** Many `die` calls are single line usage
errors where the message is the instruction, and the TAP `fail` helper takes
optional diagnostic lines that most callers use for the measurement rather than
for an action. But roughly a third of assertions leave the reader to work out
what to do next.

⭐ The ones that matter most do carry it. Every mirror failure prints the exact
`curl` that reproduces it. Every pin failure prints both hashes. The keyring
failure prints the re-derivation steps. The executable bit failure prints
`git update-index --chmod=+x`.

## What this review did NOT look at

- ⛔ **Whether the documentation is correct**, only whether files explain
  themselves. Review 1 covers correctness, and found one wrong claim.
- ⛔ **Whether a newcomer can actually run the build.** No one has cloned this
  repository fresh and followed the README from nothing.
- **The 101 failure messages one by one.** The ratio is counted, not read.
- **HISTORY/ itself.** Whether a reader can navigate five history documents
  without an index was not considered. There is no index.
- **Whether the freshness jobs actually run.** They are scheduled and have never
  fired. Only `check-keyring-pin` and `check-image-pins` have been run by hand.
