# Review 11: adding the fifth architecture

**Lens.** Somebody sits down tomorrow to add `loong64`. How many places name the
four architectures, which of them fail loudly when a fifth appears, and which
quietly build four images and call it a release.

**Date.** 2026-08-27. Written against section 1 of the brief, which is the next
task, so that whoever takes it starts from a map rather than a grep.

---

## What was checked

Every place in the tree that names the architecture set, and what each one does
when a fifth is added but not added there.

```bash
grep -rn 'amd64 arm64 armv7 riscv64' scripts tests .github Dockerfile
```

| file | places | what happens if the fifth is missed |
| --- | --- | --- |
| `.github/workflows/build-deploy.yml` | the matrix at 182, and the loops at 127, 353, 384 | not built, no anchor, no tags, and the index check never looks for it. ⛔ **All four silent** |
| `.github/workflows/freshness-mirrors.yml` | 46, 77, 127 | its mirrorlist is never refreshed or probed. ⛔ **Silent** |
| `scripts/gen-mirrorlist` | the `all` loop at 317, and the usage string at 314 | `gen-mirrorlist all` skips it. ⛔ **Silent** |
| `scripts/tag-names` | the alias table at 38 to 41 | ⭐ **loud.** An unknown architecture is a `die` |
| `tests/static/60-tag-families.sh` | 53, 98, and a `reproduce:` line at 104 | ⭐ loud, but only for the four names it hardcodes |
| `tests/static/80-docs-claims.sh` | 184 | ⭐ loud, documented tags and emitted tags must be one set |
| `tests/static/90-package-lists.sh` | 68 | ⭐ loud, one bootstrap list per matrix architecture |

⭐ **The scripts and the tests are loud. The workflows are silent.** 8 of the 15
places fail silently. 7 of those 8 are a `for` loop in YAML, and the eighth is
`gen-mirrorlist all`. Every place that refuses is a script that `die`s or a test.

⚠ **This table was wrong when this review was first written**, and the error is
left recorded rather than quietly corrected: it said eleven places, it counted
files and occurrences interchangeably, and it missed `scripts/gen-mirrorlist`
altogether. Re-derived by grepping for the literal four name list, then adding
the two places a grep for it cannot see, the build matrix and the alias table.

---

## What was found and not changed

⛔ **The architecture set is written out 15 times across 6 files.** Ten of those
are loops over the same four names. There is no single list, so adding a fifth
means finding all of them, and missing one of the silent eight produces a
release that looks complete and is not.

⚠ **This was not fixed here, deliberately.** Two reasons. The obvious fix is one
list read by everything, and the workflow matrix cannot read a shell variable:
it needs the list at expression time, which means a job output or a checked in
JSON, and that is a change to the shape of the publish. Second, section 1 of the
brief is going to touch every one of these files anyway, and a refactor landing
just before that is a merge conflict with no test behind it yet.

⭐ **What to do instead, and it is cheap:** before adding the fifth, add a static
test that asserts the same architecture set appears in every one of those
places. It fails immediately, names the places that disagree, and it is the test
that makes the refactor safe rather than the refactor itself.

⚠ **`tests/static/60-tag-families.sh` hardcodes the four in three places**, so a
fifth architecture's aliases are unasserted until someone edits it. That file
has 24 assertions and is the most valuable one to get right for a new port.

⚠ **Nothing checks that the matrix and `rootfs/` agree.** `rootfs/loong64/`
could exist with no matrix entry, or the reverse. `90-package-lists.sh` covers
the bootstrap list against the matrix, which is the closest thing, and it reads
the matrix from the workflow.

---

## What this review did NOT look at

- **Whether `loong64` builds.** Emulation for it was not tested at all, and the
  brief records that as the first thing to verify. This review is about the
  tree, not the port.
- **`powerpc`.** Blocked on a keyring that was not re-measured today. See the
  brief, section 1b.
- **The `Dockerfile`.** It takes `TARGETARCH` and `TARGETVARIANT` from buildx
  and names no architecture, so it needs nothing for a fifth. That is why it is
  absent from the table above rather than passing in it.
- **Registry platform strings.** Whether `linux/loong64` or
  `linux/loongarch64` is what the registries accept was not checked.
- **The image suite.** It takes `IMAGE` and `PLATFORM` and names no
  architecture, so it works on a fifth for free.

## Change summary

No code changed in this review. Its output is the map above and one concrete
next step for section 1.

| file | added | removed |
| --- | --- | --- |
| `HISTORY/reviews/11-adding-the-fifth-architecture.md` | new | - |
