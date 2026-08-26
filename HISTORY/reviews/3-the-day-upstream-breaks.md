# Review 3: the day upstream breaks

**Lens.** Take each external dependency away in turn. Does CI fail loudly and
specifically, or does it publish something wrong, or publish nothing while
reporting success?

**Method.** Each row was produced by removing the dependency and running the
thing that depends on it. Nothing here is reasoned from reading the code.

**Date.** 2026-08-26.

---

## The dependency list, and what each removal does

| # | dependency | removed how | result | loud? |
| --- | --- | --- | --- | --- |
| 1 | every mirror for one architecture | mirrorlist replaced with two `.invalid` hosts | `resolve-anchor` exit **1**, naming each server and the curl error | yes |
| 2 | the anchor package leaving the database | `ANCHOR_PACKAGE` set to a name no database carries | `resolve-anchor` exit **1**, "not found in ..., trying the next server" per server, then a final message | yes |
| 3 | the repository database, during evidence | mirrorlist replaced with one `.invalid` host | `gen-evidence` exit **1**, "could not fetch the core database for riscv64 from any server" | yes |
| 4 | a package present in the image but in no database | a `ghost-package` entry appended to an evidence file | `40-evidence.sh`: `not ok 13 ... incomplete entries: ghost-package` | yes |
| 5 | the pinned ARM keyring package being replaced | fixture mirror serving different bytes | `install-alarm-keyring` exit **1**, "checksum mismatch", printing both hashes | yes |
| 6 | the pinned ARM keyring package being withdrawn | fixture mirror listing only a newer name | `check-keyring-pin` exit **4**, "GONE ... the build is broken now" | yes |
| 7 | a newer ARM keyring appearing | fixture mirror listing both | `check-keyring-pin` exit **3**, "behind, the pinned package is still fetchable" | yes |
| 8 | one architecture failing to build | `bootstrap/riscv64/etc/bootstrap-packages.txt` set to a non-existent package, on a throwaway branch, real CI run | riscv64 job **failure**, other three **success**, publish job **skipped** | yes |
| 9 | a mirror blocking the CI region | observed, not injected: `ftp.myrveln.se` answers 200 from a workstation and 403 from a GitHub runner | named in the log, floor assertion still passes | yes, as a diagnostic |

## Item 8 is the one that matters

The 59 day outage was a green run that published nothing. The inverse is a run
that publishes a partial release. Both are now prevented by the same structure:
the publish job has `needs: [resolve, build]` over the whole matrix and no
`if: always()`.

Measured on run `32991693708`:

```
Resolve inputs: success
Build riscv64:  failure
Build amd64:    success
Build armv7:    success
Build arm64:    success
Create tags:    skipped
```

`fail-fast` is off, so the other three still ran and reported. That is
deliberate: one run names every broken architecture rather than stopping at the
first.

⭐ **And no tag moved.** Six tags in the scratch repository were recorded by
digest before the run and compared after:

```bash
diff .tmp/phasec/scratch-before.txt .tmp/phasec/scratch-after.txt   # identical
```

`latest`, `v2026.08.26`, `x86_64`, `aarch64`, `riscv64` and `armv7h` all still
point at the same digests they did before the broken run.

## Where a failure is loud but not specific

⚠ **Item 1, at the workflow level.** `resolve-anchor` fails with a good message,
but the step that calls it is a `for` loop over four architectures:

```
.github/workflows/build-deploy.yml:88   anchor="$(scripts/resolve-anchor "$arch")"
```

Under `set -euo pipefail` the whole step dies on the first architecture that
cannot resolve. The message on stderr names the architecture, so it is
recoverable from the log, but the run stops before it learns whether the other
three could resolve. Compare the build matrix, which deliberately reports every
architecture. ⚠ Not changed, because a run that cannot pin one architecture
cannot produce a coherent release anyway, and continuing would only produce more
output for the same verdict.

## What does not fail loudly, and why that is accepted

- **A single mirror going away.** By design. `40-mirrors-reachable.sh` names it
  as a diagnostic and only fails when a list drops below two reachable servers
  or below half of what it ships. A single entry failing does not produce a
  wrong image, and treating it as fatal made the repository unbuildable when one
  mirror blocked GitHub's network. See the commit `assert a reachable floor per
  mirror list, not every entry`.
- **A stale database served over plain http on the two ARM ports.** Covered in
  review 2. It is a rollback, every signature still verifies, and CI reports
  success. It is visible afterwards in the evidence file and in the anchor tag,
  and it is not prevented.

## What this review did NOT look at

- ⛔ **Docker Hub being unavailable during publish.** The cross-registry step
  has never run, in any form. A dry run pushes to one registry by design.
- ⛔ **GHCR being unavailable.** The whole topology stages digests there. If
  GHCR is down there is no build at all, and no test covers what that looks
  like.
- **The GitHub Actions cache being unavailable or poisoned.** `type=gha` cache
  misses are silent by design and that is correct, but a poisoned entry was not
  considered here.
- **Rate limiting.** `archlinux.org/mirrors/status/json/` answers 429 under
  load. `gen-mirrorlist` dies rather than yielding a short list, which is right,
  but that path was not exercised.
- **A mirror that is slow rather than absent.** Every injection here was a hard
  failure. A mirror that accepts the connection and then stalls is the case
  Phase B hit three times against Arch Linux 32, and no timeout policy was
  tested here.
- **Partial or corrupt responses.** A truncated `core.db`, a `.sig` that is
  zero bytes, a `base.db` that is Zstandard where every sibling is gzip. Those
  shapes have been seen in this project and none is covered by a test.
