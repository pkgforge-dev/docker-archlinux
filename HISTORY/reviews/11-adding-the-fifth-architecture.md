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

| place | what happens if the fifth is missed |
| --- | --- |
| `.github/workflows/build-deploy.yml`, matrix | the fifth is simply not built. ⛔ **Silent.** A release goes out with four |
| `build-deploy.yml:127`, the anchor loop | the fifth has no anchor, so no pinned tag family. ⛔ Silent |
| `build-deploy.yml:353,384`, the tag and verify loops | the fifth's tags are never created, and the index check does not look for it. ⛔ Silent |
| `freshness-mirrors.yml`, three loops | the fifth's mirrorlist is never refreshed or probed. ⛔ Silent |
| `scripts/tag-names`, `aliases_for` | ⭐ **loud.** An unknown architecture is a `die` |
| `scripts/resolve-anchor` | ⭐ loud. No `pacman.conf` for it is a `die` |
| `scripts/gen-evidence` | ⭐ loud, same shape |
| `tests/static/90-package-lists.sh` | ⭐ loud. It asserts one bootstrap list per matrix architecture |
| `tests/static/60-tag-families.sh` | ⭐ loud, 24 assertions, but only for the four it names |
| `tests/static/45-pacman-conf-shape.sh` | ⭐ loud in a useful way. It compares whatever `pacman.conf` files exist, so a fifth is held to the same `[options]` block the moment it is added |
| `tests/static/80-docs-claims.sh` | ⭐ loud. Documented tags and emitted tags must be the same set |

⭐ **The scripts and the tests are loud. The workflows are silent.** Every place
that would let a four architecture release go out unnoticed is a `for` loop in
YAML, and every place that refuses is shell or a test.

---

## What was found and not changed

⛔ **The architecture set is written out eleven times.** Nine of those are loops
over the same four names. There is no single list, so adding a fifth means
finding all of them, and missing one of the workflow loops produces a release
that looks complete and is not.

⚠ **This was not fixed here, deliberately.** Two reasons. The obvious fix is one
list read by everything, and the workflow matrix cannot read a shell variable:
it needs the list at expression time, which means a job output or a checked in
JSON, and that is a change to the shape of the publish. Second, section 1 of the
brief is going to touch every one of these files anyway, and a refactor landing
just before that is a merge conflict with no test behind it yet.

⭐ **What to do instead, and it is cheap:** before adding the fifth, add a static
test that asserts the same architecture set appears in every one of those eleven
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
