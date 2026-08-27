# Review 13: the brief, checked line by line against the tree

**Lens.** Review 12 asked whether `HISTORY/misc/outstanding-work.md` can be read
and acted on. This one asks whether what it says is **true**. Every number, every
path, every command, checked against the repository rather than against memory.

**Date.** 2026-08-27. Second of two reviews of that file.

---

## What was checked, and how

Mechanically where possible, because a number in a document is exactly the kind
of claim that rots without anybody noticing.

```bash
python .tmp/verify_brief.py   # link targets, backticked paths, section numbering, counts
```

⭐ **Every count in the file matches the tree.**

| claim | in the file | measured |
| --- | --- | --- |
| tracked files | 107 | 107 |
| scripts | 7 | 7 |
| workflows | 5 | 5 |
| test files | 24 | 24 |
| static test files | 18 | 18 |
| image test files | 6 | 6 |

⭐ **Every markdown link target exists.** Checked by resolving each one against
the file's own directory. Zero missing.

⭐ **Every fenced `bash` block parses.** Checked with `bash -n` on each block
extracted from the file. This matters more here than it looks: the file's own
rule is that every claim carries the command that proves it, so a block that
does not parse is a claim that cannot be checked.

⭐ **Section numbering is sequential and every cross-reference is correct after
today's reordering.** Four "see section N" references resolved by hand.

⭐ **The `loong64` measurements in section 1 were taken today**, not copied from
the material that prompted the task. Five mirrors probed, `core.db` read, the
package list extracted, `.sig` checked for three packages. The keyring finding,
which is the one that decides whether the port is possible at all, came out of
that database rather than out of a web page.

---

## What this review changed

⚠ **Two operational facts a cold reader needs were missing.** The "Running the
tests" section described the image suite as it was this morning. It did not say
that `tests/image/60-defect-parity.sh` now **starts** the image where every
other image test does not, nor that the static suite now needs `tar`. Somebody
running the suite on a machine without `tar`, or wondering why one image test
takes 32 seconds on `riscv64`, would have had to read the source to find out.
Both are now stated.

---

## What was found and not changed

⚠ **Four numbers in the file are dated observations, not invariants, and cannot
be checked mechanically:**

| claim | why it cannot be re-checked here |
| --- | --- |
| "Both hold 161 tags" | true when measured today, and it changes on the next publish by design |
| "187 code hits on 2026-08-26" | a GitHub code search, rate limited and not reproducible offline |
| "Baseline: 245 seconds on run `32992678276`" | a CI run, not reproducible locally |
| the run IDs in the done table | the same |

Each carries its date or its run ID, which is the file's own rule for a value
that moves. ⛔ Nothing was found that states a moving number as though it were
fixed.

⚠ **The done table now carries thirteen rows and is the least verifiable part of
the file.** Every row points at an artefact, and the artefacts exist, but "this
was done" is not a thing a test can assert. The mitigation is that each row
names a test file or a document, and both are checked above.

⚠ **The traps section was not re-verified.** Eight traps, each one a thing that
cost time. They were true when written. ⭐ Two of them cost time again **today**,
which is evidence enough that they are current: a doubled backslash arrived
halved twice while editing this very file, and native `jq` writing CRLF turned a
161 tag sweep into 161 identical failures that looked like 161 missing tags.

⚠ **The file grew, from 675 lines to 788.** Review 12 covers why and says
plainly that a reduction was asked for and did not happen in total, only in the
finished sections.

---

## What this review did NOT look at

- **`HISTORY/defect-parity.md`, `HISTORY/arm-rollback.md`, and the other
  documents this file links to.** Their existence was checked. Their contents
  were not re-verified here; they were written today against measurements taken
  today.
- **Whether the standing policy and the decisions already made are still what
  the maintainer wants.** They are the maintainer's, and reviewing them is not
  this file's job.
- **The eight reviews that predate today.** Not re-read.
- **Prose quality.** Voice rules are checked by hand and by
  `tests/static/80-docs-claims.sh` for the README files only. This file is not
  covered by that test, and no test asserts its markers or its tone.
  ⚠ That is a real gap: the voice rules exist and nothing enforces them here.

## Change summary

| file | added | removed |
| --- | --- | --- |
| `HISTORY/misc/outstanding-work.md` | 11 | 0 |
| `HISTORY/reviews/13-the-brief-checked-against-the-tree.md` | new | - |
