# Review 12: the brief, read by somebody with no repository

**Lens.** `HISTORY/misc/outstanding-work.md` says of itself: *"Standalone by
design: a reader needs nothing but this file and the repository."* Read it as
somebody who has been handed the file and a clone and nothing else. No memory of
this session, no context, no chat log. Can they start work, and can they start
on the right thing.

**Date.** 2026-08-27. First of two reviews of that file, because it was
substantially rewritten today and it is the only thing that carries the next
session.

---

## What was checked

The file end to end, as prose, against what a cold reader needs.

⭐ **The order is stated and the order is real.** "The order below is the order
to take them in" is followed by eight sections numbered 1 to 8, sequential, with
no gaps. Verified rather than eyeballed: the section numbers extracted in order
are `[1, 2, 3, 4, 5, 6, 7, 8]`.

⭐ **Every cross-reference points where it says.** Four references of the shape
"see section N" were resolved by hand against the current numbering. The
powerpc mirrors note points at Redundancy, the outage fallback note points at
Static pacman, and both are correct after today's renumbering. This is the
failure mode a reordering introduces and it is the first thing that would have
broken.

⭐ **Every link resolves.** All markdown link targets in the file exist on disk,
checked mechanically.

⭐ **The finished work is summarised and the unfinished keeps its detail**, which
is the file's own stated rule. Sections 1 and 3 of the previous version were
finished today and are now one table row each. Section 2 of the previous version
was half finished and is now two bullets instead of four.

---

## What this review changed

⚠ **The reviews section was stale the moment the reviews were written.** It
said "Eight lenses are used" and listed eight, and it suggested three unused
lenses of which two had just been used. A cold reader would have picked a lens
that already existed. It now lists thirteen and suggests three that are
genuinely unused.

⚠ **The done table said "eight" reviews.** Same fix.

---

## What was found and not changed

⚠ **Five backticked paths in the file do not exist in this repository**, and all
five are correct:

| path | where it actually is |
| --- | --- |
| `Github/Runners/bootstrap/archlinux.sh` | `pkgforge/devscripts` |
| `.github/workflows/release.yml` | `pkgforge-dev/cross-libc-dlopen` |
| `scripts/release-notes.sh` | the same |
| `rootfs/loong64/etc/pacman.conf` | does not exist yet, section 1 creates it |
| `bootstrap/loong64/etc/bootstrap-packages.txt` | the same |

Each is named next to the repository it belongs to, or inside a numbered list of
things to create. A reader following one would find the sentence around it says
so. ⚠ It is still the thing most likely to send somebody looking for a file that
is not there, and no test can tell a path that is elsewhere from a path that is
wrong.

⚠ **The file is 788 lines and it grew today**, from 675. It was asked to shrink.
It did shrink where it was asked to, in the finished sections, and it grew more
than that in section 1, which is a new task described from scratch. ⭐ The rule
the file states is about *kind*, not size: finished work summarised, unfinished
work in full. By that rule it is correct. By line count it is not smaller, and
that is worth saying plainly rather than reporting a reduction that did not
happen.

⚠ **"⛔ The order below is the order to take them in" now conflicts with itself
in one place.** Section 2's outage bullet says it overlaps section 8, and
section 8 is last. A reader taking them strictly in order will decide the outage
fallback before the thing it overlaps exists. The note says so, which is the
best that can be done without reordering against an instruction.

---

## What this review did NOT look at

- **Whether the claims are true.** That is review 13. This one is about whether
  the file can be read and acted on, not whether what it says matches the tree.
- **The rest of `HISTORY/`.** The other documents are not claimed to be
  standalone and were not read for this.
- **`README.md`.** A different audience, and it has its own reviews.
- **Whether the eight sections are the right eight.** The maintainer set them.

## Change summary

| file | added | removed |
| --- | --- | --- |
| `HISTORY/misc/outstanding-work.md` | 12 | 8 |
| `HISTORY/reviews/12-the-brief-read-by-somebody-with-no-repository.md` | new | - |
