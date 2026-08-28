# Review 18: a fault injected in the wrong place

**Lens.** A fault injection is a test of a test. It can pass for the wrong
reason: the fault fires somewhere upstream of the behaviour under test, the run
goes red, and the report reads as though the invariant had been exercised. This
review asks, of the three proofs taken on 2026-08-28, whether each one reached
the thing it names.

**Date.** 2026-08-28, against `756bef1`.

⚠ Distinct from review 5, which read the test suite for what it asserts. This
one reads three CI runs and asks where the failure actually landed.

---

## What was opened

- `.github/workflows/build-deploy.yml`, 480 lines, whole. Specifically `needs:`
  at lines 171 and 339, `fail-fast: false` at 176, the `Export the digest` step,
  and `verify_index` at 442 to 474.
- `tests/static/90-package-lists.sh`, run against the injected tree.
- `tests/static/68-evidence-snapshot.sh`, assertions 4 and 5, run against the
  reverted tree.
- The three runs, by job and by step:
  `33179363541`, `33178993776`, `33180365462`.
- `HISTORY/tests-seen-to-fail.md`, the rows added by this session.

## Finding 1: the prescribed injection would not have reached the matrix

⛔ **The instruction was to write two lines into
`bootstrap/loong64/etc/bootstrap-packages.txt`**, `base` and a package name that
does not exist. That drops `archlinux-lcpu-keyring`.

```bash
printf 'base\nno-such-package\n' > bootstrap/loong64/etc/bootstrap-packages.txt
bash tests/run.sh static
```

```
not ok 11 - bootstrap/loong64 names archlinux-lcpu-keyring
#   bootstrap/keyrings/archlinux-lcpu.pin serves Architecture = loong64, which rootfs/loong64 sets
#   without it the image cannot verify its own updates after the build
```

The `resolve` job runs `tests/run.sh static` at its last step, before any build
job starts. ⛔ **The run would have gone red with no build job having run at
all**, and "the other four still ran" could not have been observed, because
`build` has `needs: resolve`.

⭐ **The precedent did not catch this because it could not.**
`bootstrap/riscv64/etc/bootstrap-packages.txt` names one package and no keyring,
so replacing its contents cannot break an assertion about a keyring. The
prescribed command was a correct generalisation of a case that happened not to
exercise the guard.

**What was done instead.** The keyring line was kept and the bogus name
appended. The static suite passes, `resolve` succeeds, and the failure lands at
`Build and push by digest` with `error: target not found: no-such-package`.

## Finding 2: the same shape appeared again, in the revert

⛔ **Reverting the evidence snapshot by editing the workflow alone is refused
in `resolve` for the same reason.** `tests/static/68-evidence-snapshot.sh`
assertion 4 asserts the build job builds the `dbsnapshot` target and assertion 5
asserts the evidence step is given `DB_SNAPSHOT`. Removing the wiring fails both.

```
not ok 4 - the build job builds the dbsnapshot target
not ok 5 - the evidence step is given DB_SNAPSHOT
```

⭐ **That is the guard working, and it is worth stating plainly**: a half
reverted snapshot cannot reach a runner. It also means the revert had to be the
whole of `30d75ed`, which is what run `33180365462` carried.

⚠ **Review 14 reasoned about this revert from the diff.** It did not predict
that the static suite refuses the partial form. Nothing it concluded is wrong;
the path is one step longer than it described.

## Finding 3: what the partial failure proof does and does not cover

**Covered, and read back per job:** `Build loong64` fails at step 6 of 12. Its
seven remaining steps, including `Upload the digest`, are `skipped`. The other
four builds succeed. `Create tags` is `skipped`, not failed, so it never
started. Real GHCR held 161 tags before and after.

⚠ **Not covered: the four successful builds still pushed.** `push-by-digest`
puts four manifests and their blobs on the scratch registry during a run that
publishes nothing. The invariant is about **tags**, and it holds. ⭐ Untagged
blobs on a scratch repository are the intended cost of staging by digest, and no
consumer can name them, but "publishes nothing" is shorter than what happens.

⚠ **Not covered: the digest guard's own message.** `Create the per architecture
tags` carries `no digest for $arch, refusing to tag a partial release`. That line
has still never printed, because `needs:` stops the job before it can. It is
defence in depth behind a gate that has never let anything through.

## Finding 4: the index is verified, the per architecture tags are not

`verify_index` inspects one tag per registry, the dated index, and asserts five
platforms. Nothing reads back `:loong64`, `:loongarch64`, or any of the dated or
anchor spellings.

```bash
grep -n 'verify_index' .github/workflows/build-deploy.yml   # 442, 475, 477
```

⚠ **A hard failure is still caught**, because `Create the per architecture tags`
runs under `set -euo pipefail` and `imagetools create` exits non-zero. What is
not caught is a copy that returns success with a tag missing on one registry.

⭐ **The six loong64 tags on Docker Hub were confirmed for this session by an
out of band listing**, not by the workflow:

```bash
url="https://hub.docker.com/v2/repositories/pkgforge/archlinux-ci/tags?page_size=100"
while [ -n "$url" ] && [ "$url" != "null" ]; do
  curl -s "$url" -o p.json; jq -r '.results[].name' p.json; url=$(jq -r '.next' p.json)
done | grep loong
```

⚠ This restates a gap `HISTORY/tests-seen-to-fail.md` already names as unproven,
a copy that fails partway. It is recorded here as the same gap seen from the
publish side rather than as a new one.

## What was fixed, and where the rest is tracked

| finding | outcome |
| --- | --- |
| 1, the prescribed injection lands in `resolve` | ⭐ **fixed before the run.** The keyring line was kept and the bogus name appended, so the failure lands in `build`. Recorded in `HISTORY/tests-seen-to-fail.md` so the next session does not repeat it |
| 2, a partial revert is refused by the static suite | ⭐ **fixed before the run.** The whole of `30d75ed` was reverted instead. The behaviour itself is correct and needs no change |
| 3, untagged blobs on the scratch registry, and a digest guard that has never printed | **not fixed, and no change proposed.** Both are consequences of staging by digest and of `needs:` holding. Recorded here only |
| 4, per architecture tags are not read back | **not fixed.** Tracked as the existing "a copy that fails partway" gap at the end of `HISTORY/tests-seen-to-fail.md` |

## What was ruled out

- **A green run that proved nothing.** All three runs were read job by job and
  step by step, not by conclusion. In `33179363541` the failing step is named
  and its error line quoted.
- **The evidence proof reading a snapshot after all.** The `Record the evidence`
  step's env block in run `33180365462` was read in the log: it carries
  `IMAGE`, `PLATFORM`, `DOCKER_ARCH`, `CONTAINER_RUNTIME`, `SOURCE_COMMIT`,
  `BUILD_DATE`, and no `DB_SNAPSHOT`. There is no export step in that run.
- **The dry runs touching a real repository.** GHCR and Docker Hub both held
  161 tags before and after, measured on both.
- **A number carried from the brief.** Every figure here was re-measured. The
  161 was re-read from both registries rather than quoted.

## ⚠ What this did not look at

- **The other injections in `HISTORY/tests-seen-to-fail.md`.** Only the three
  rows added on 2026-08-28 were audited. The earlier rows were not re-run.
- **Whether the static suite's own assertions are right.** Assertion 11 of
  `90-package-lists.sh` and assertions 4 and 5 of `68-evidence-snapshot.sh` were
  observed firing. Whether they assert the right thing is review 5's question.
- **The image suite.** Not run locally this session. It ran in CI inside each of
  the three dry runs, on all five architectures.
- **A copy that fails partway.** Still not produced deliberately, here or
  anywhere.

## Change summary

Files touched by the change this reviews: 4, all under `HISTORY/`. Lines added
463, removed 0. No code, no workflow and no test changed on `main`; the two
throwaway branches that carried the injections are deleted.
