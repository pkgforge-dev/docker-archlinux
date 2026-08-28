# Review 16: the release as one unit, now that it is five things

**Lens.** One run is one release. It was four architectures and it is now five.
What in the tree still believes it is four, what does the extra one cost, and
does the invariant that a run losing one architecture publishes nothing still
hold when there is one more to lose.

**Date.** 2026-08-28, against the tree that adds loong64 and against dry run
`33165970427`.

⚠ Distinct from review 11, which asked how to **add** a fifth architecture and
produced the map. This one asks what the fifth **did** to the release.

---

## What was checked

### 1. What still says four

```bash
grep -rn '\bfour\b\|\bFour\b' scripts tests .github Dockerfile README.md examples bootstrap
```

23 hits in ten files. Sorted by whether "four" was ever about the architecture
set:

| where | about the architectures | verdict |
| --- | --- | --- |
| `README.md`, the tag table, 2 rows | yes | ⛔ **user facing and wrong.** Fixed |
| `.github/workflows/build-deploy.yml`, 2 comments | yes | fixed |
| `tests/static/45-pacman-conf-shape.sh`, 8 places including one `fail` diagnostic | yes | fixed |
| `tests/image/50-consumer-contract.sh`, 1 comment | yes | fixed |
| `tests/README.md`, 2 rows | yes | fixed |
| `tests/static/75-architecture-set.sh`, 2 comments | yes | fixed |
| `tests/static/75-architecture-set.sh:20`, "four spellings" | ⭐ no, four spellings of **one** architecture | left |
| `tests/static/35-publish-targets.sh:43`, "four names" | no, four image name variables | left |
| `tests/static/67-mangled-responses.sh:75` | no, four mangled mirrors | left |
| `tests/static/68-evidence-snapshot.sh:15` | no, four edits that break the snapshot | left |
| `examples/README.md:10` | no, four things that never move | left |

⛔ **The README rows are the finding.** They were the only count of architectures
anywhere a consumer reads, and they said four while the index carried five. A
consumer on loong64 would have read a table that did not include them.

⭐ **Nothing was recounted from four to five.** Every fix removed the number:
"an index over every platform", "every architecture the matrix builds", "the
shipped `pacman.conf` files". A count in prose is a thing that goes stale, and
`75-architecture-set.sh` already refuses to let a **list** go stale. This closes
the gap between the two.

### 2. Is it still one release

| question | measured |
| --- | --- |
| one anchor across five | ⭐ yes. `scripts/resolve-anchor` returns `7.1.0.r9.g54d9411-2` for all five |
| the index carries every platform | ⭐ yes. `index platforms: amd64 arm/v7 arm64 loong64 riscv64` in the dry run |
| a new architecture with no published floor | ⭐ handled. `no floor  loong64  nothing published yet, resolved 7.1.0.r9.g54d9411-2` |
| the merge job needs the whole matrix | unchanged: `needs: [resolve, build]`, no `if: always()` |

```bash
for a in amd64 arm64 armv7 loong64 riscv64; do printf '%-8s %s\n' "$a" "$(scripts/resolve-anchor "$a")"; done
CONTAINER_RUNTIME=podman scripts/check-anchor-floor "$ANCHORS"
```

⭐ **`scripts/check-anchor-floor` needed no edit.** It reads its architecture set
from the JSON it is handed, so the fifth arrived and it reported on it. That is
the shape review 11 argued for and it is the only one of the sites that already
had it.

### 3. What the fifth cost

```bash
gh run view <id> --json createdAt,updatedAt --jq '"\(.createdAt) -> \(.updatedAt)"'
```

| run | architectures | end to end |
| --- | --- | --- |
| `32992678276`, 2026-08-26 | 4 | 434 s |
| `33162764880`, 2026-08-28, with the evidence snapshot export | 4 | 431 s |
| `33165970427`, 2026-08-28 | 5 | ⭐ **416 s** |

⭐ **The fifth architecture cost nothing measurable.** The matrix is parallel and
the run is as long as its slowest job. loong64's build step took 265 seconds,
shorter than riscv64's 335 seconds in the baseline run, so it never became the
critical path.

⚠ **A brief claim that does not reproduce.** The work list records "Baseline:
245 seconds wall clock on run `32992678276`". Three derivations were tried
against that run and none gives 245: end to end is 434 s, the longest build job
is 335 s (riscv64), and the shortest is 142 s (amd64). The optimisation target in
that section is against a number nothing in the run produces.

---

## What was found and changed

| file | change |
| --- | --- |
| `README.md` | two tag table rows, "all four platforms" to "every platform" |
| `.github/workflows/build-deploy.yml` | two comments, the index check and the debloat note |
| `tests/README.md` | two rows |
| `tests/static/45-pacman-conf-shape.sh` | seven comments and one `fail` diagnostic |
| `tests/static/75-architecture-set.sh` | two comments |
| `tests/image/50-consumer-contract.sh` | one comment |

The static suite, both linters and the image suite were re-run after these, all
green: `20 files, failed: 0`, shellcheck 0, actionlint 0.

## What was ruled out

- **A hardcoded 4 in an assertion.** `grep -rn '= *4\b\|-eq 4\|"4"' tests/ scripts/`
  returns one hit, `gen-evidence` checking it was given four arguments, which is
  its own argument count and not an architecture count.
- **`scripts/check-anchor-floor` needing a fifth entry.** Run with five, reported
  five, one of them with no floor.
- **The publish job losing the invariant.** `needs:` still names the whole
  matrix and there is still no `if: always()`, so the topology is what it was.
- **A tag collision between the two new names and the existing ones.**
  `60-tag-families.sh` asserts no alias is claimed twice, over all five, and
  passes. `loongarch64` and `loong64` are claimed by nothing else.

## ⚠ What this did not look at

- ⛔ **A partial failure with five architectures was not injected.** The
  invariant is recorded in `HISTORY/tests-seen-to-fail.md` against a four
  architecture matrix, where a deliberately broken riscv64 bootstrap stopped the
  publish. Nothing about that mechanism changed, and it was not re-run with five.
  That is the one claim in this review resting on reading rather than measuring.
- **Docker Hub.** `publish_hub` was false in the dry run, so the cross registry
  copy was not exercised with five architectures.
- **A real scheduled publish.** No loong64 image is published yet.
- **Whether 416 seconds holds.** One run, one day, warm GHA caches for four of
  the five architectures and a cold one for loong64.
- **Disk pressure on the runner.** Still unmeasured, as the workflow's own
  comment says.

## Change summary

Files touched: 6. Lines added: 23. Lines removed: 23.

The sweep went from 23 hits to 5, and every one of the 5 that remains is about
something that is genuinely four.
