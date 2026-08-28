# Review 17: a report entering the record as though it were a measurement

**Lens.** Somebody hands the session a URL and a description of what is behind
it. The session is told not to look. What ends up written down, and can the next
session tell the difference between what was checked and what it was told.

**Date.** 2026-08-28. Only `.tmp/PROMPT_COMPLETION.md` was touched in the change
this reviews, so only that file is reviewed.

⚠ Distinct from review 12, which read the brief as somebody with no repository,
and review 13, which checked it line by line against the tree. This one asks
whether one specific new claim is safe to leave in it.

---

## What was checked

### 1. The claim, and what is actually behind it

The maintainer reported `https://github.com/Aseem0xff/pacman-static` as 0-BSD, a
proof of concept for this repository, and said most of the hard work is done. One
thing was fetched, because fetching it was the instruction:

```bash
curl -sS -o r.md -w '%{http_code} %{size_download}\n' --connect-timeout 10 --max-time 60 \
  -L "https://github.com/Aseem0xff/pacman-static/raw/main/README.md?CACHE_BUST=$(date +%s)"
```

`200 67`. The whole file:

```
This is a POC for https://github.com/pkgforge-dev/docker-archlinux
```

⛔ **The README corroborates one of the four claims and it is the smallest one.**
It confirms the repository exists and says it is a proof of concept for this
project. It says nothing about `pacman`, nothing about a licence, nothing about
which architectures build, and carries no instructions. The 0-BSD claim, the
"most of the hard work is done" claim, and the "unblocks everything" claim are
all unattested by anything anybody has read.

⚠ **That is not a criticism of the report.** It may be entirely right. The point
is only that the file must not read as though it had been checked, because a
session starting cold cannot tell the difference and this brief's first rule is
that every claim in it is a lead rather than a fact.

### 2. Does the brief distinguish the two

Three places now name it. Each was read whole rather than grepped:

| line | what it says | marks it unverified |
| --- | --- | --- |
| 429, decision 7 | a second reference exists and is unmined | ⭐ yes, "**unmined**", and "does not overturn this decision by existing" |
| 637, TODO 2 | the report, then the 67 bytes, then what is unchecked | ⭐ yes, "Everything else about it is a report, not a measurement" |
| 1065, Where things stand | the pointer a cold session meets first | ⭐ yes, "everything the report claims about it is unchecked" |

⭐ **The verified part carries its own reproduce command**, and that command was
run again during this review: `200 67`, byte identical to the first fetch. A
reader can re-derive the one fact without trusting the file.

⛔ **One trap is written down explicitly**, because it is the trap the previous
reference set. Decision 7 exists because `packages-core-pacman-static` declared
`GPL-2.0-or-later` in its `PKGBUILD` and shipped **no** LICENSE file. TODO 2 now
says to read the LICENSE itself rather than the prose, and says separately that
0-BSD on a recipe does not change what licence the `pacman` binary carries.

### 3. Three reorderings in one session, and whether the numbering survived

The TODO list was reordered three times on 2026-08-28: loong64 removed to
Completed, three tasks inserted, then static pacman moved from 8 to 2. Each
reordering renumbers headings and orphans every cross-reference.

```bash
sed -n '/^## TODO/,$p' .tmp/PROMPT_COMPLETION.md | awk '/^### [0-9]+\. /{ ... }'
for n in $(grep -o 'TODO [0-9]*' .tmp/PROMPT_COMPLETION.md | awk '{ print $2 }' | sort -un); do ... done
```

| check | result |
| --- | --- |
| headings sequential | ⭐ 13, no gap |
| duplicate heading numbers | ⭐ 0 |
| cross-references resolving | ⭐ 3 distinct targets, all resolve, all to the intended task |
| Completed table | ⭐ rows run 1..30, untouched by any of the three |

⚠ **This is the third time in one session that a renumbering needed a manual
remap.** It worked each time and it was checked each time, but a cross-reference
in prose is a thing that goes silently wrong, and nothing in the repository
checks the brief. That is by design, since `.tmp/` is scratch, and it means the
check is a human one every time.

---

## What was found and changed

Nothing was changed by this review. The three placements above already carried
their unverified markers when it ran, because the risk was the reason for writing
them that way.

## What was ruled out

- **A number nobody can reproduce.** The only number introduced is 67 bytes, and
  the command that produces it is in the file and was re-run.
- **The word "verified" used loosely.** Grepped: the reference block says "What
  is verified is only this" and then bounds it to the README. No other sentence
  about this reference uses it.
- **Decision 7 being quietly overturned.** The new reference does not touch it.
  Both the decision and TODO 2 now say that overturning it is a decision for the
  maintainer.
- **Stray characters and encoding.** Only the three permitted markers across all
  1080 lines, no em dash, no CRLF.
- **Repository drift.** `git status` is clean and `main` is still `3d98756`.
  Nothing in the tree was touched by this change.

## ⚠ What this did not look at

- ⛔ **The reference itself.** Not cloned, not read, no commit captured, no
  tracker read, no LICENSE opened. That was the instruction, and it is why
  nothing here says whether the report is right.
- **Whether the reference will still be there.** One README was fetched twice,
  eight minutes apart. A repository that appeared during a session can change or
  go away.
- **The rest of the brief.** Only the parts this change touched were read:
  decision 7, the TODO headings and cross-references, TODO 2, and "Where things
  stand". Reviews 12 and 13 cover the file as a whole, at earlier dates.
- **Whether TODO 2 at high priority is the right call.** That is the maintainer's
  ordering, applied as given.

## Change summary

Files touched: 1, `.tmp/PROMPT_COMPLETION.md`, which is not in the repository.
Lines added: 141. Lines removed: 85. 1024 lines to 1080.

⚠ This review is in the repository and the file it reviews is not, because
`.tmp/` is wiped between sessions. Reviews 12 and 13 have the same shape.

---

## Addendum, 2026-08-28: the reference was mined, and the report held

⛔ **This closes the gap named above under "What this did not look at".** The
reference was cloned, its commit captured first, its tracker read and its
LICENSE opened. `HISTORY/references/aseem-pacman-static.md` carries the full
write-up and the verdict. What belongs here is only what it says about the
question this review asked, which is whether an unchecked report was safe to
leave in the record.

**The review's own framing was four claims, one corroborated.** Measured
against the repository at `38f7e3e45730f9a6dd4d62675dc1e9594b90f4e4`:

| the claim | what measurement says |
| --- | --- |
| it exists and is a proof of concept for this repository | corroborated before, unchanged |
| **0-BSD** | ⭐ **holds.** `LICENSE` is the full 0BSD text, 12 lines. `gh api repos/Aseem0xff/pacman-static --jq '.license.spdx_id'` answers `0BSD` |
| most of the hard work is done | ⚠ **partly.** A static `pacman` 7.1.0 for five architectures with evidence files, and two of its own phases unstarted: source signatures, T-07, and reproducibility, T-16 |
| it unblocks this task | ⚠ **partly.** It covers four of this repository's five architectures. ⛔ It does not cover `armv7` |

⭐ **The trap the review named did not fire.** Decision 7 exists because
`packages-core-pacman-static` declares `GPL-2.0-or-later` in its `PKGBUILD` and
ships no LICENSE file. This repository ships one, its text is the licence it
claims, and `LICENSING.md` bounds the claim correctly: the vendored trees under
`references/` keep their own licences, and applying a patch produces a
derivative under the patched file's licence.

⚠ **And one open fault the report did not mention.** A low rate intermittent
`SIGSEGV` after `pacman -S base` completes, roughly 3 in 50, which the
repository itself calls a blocker. A report is a summary and a summary drops
things; that is the shape of the risk this review was about, and here it took
the form of an omission rather than an error.

### What this says about the practice, not about this reference

⭐ **Marking the report as a report was the right call and it cost nothing.**
Three of the four claims turned out to be right or nearly right, so the brief
would have been mostly correct had it stated them flatly. ⛔ **That is the
argument for the practice, not against it.** The session that mined it could
tell which sentences it had to verify, and it found two things a flat statement
would have hidden: the open fault above, and the `armv7` gap.

⚠ **What the mining found that no amount of care with the brief could have.**
Two facts recorded in this repository's own TODO 2 are now stale, and both were
measured against live upstream rather than against the reference's corpus:

- `manjaro-contrib/packages-core-pacman-static` is at
  `aad8fa5b24a94aa36f01b42eeae5a426b314a2c9`, `pkgrel` 15, not the recorded
  `8c7a7c2262d5d51ee4d7301d403133a9c932c2f6` at `pkgrel` 14.
- Its `riscv64` is declared in `arch=()` and cannot build:
  `openssltarget='linux64-$CARCH'` is single quoted at `PKGBUILD:251`, so
  `$CARCH` never expands.

⛔ **The brief recorded the fork's architecture list as fact.** It came from the
fork's own `arch=()`, which is observed content and is evidence of intent
rather than of behaviour. The lens of this review generalises: a report is not
the only thing that enters the record unchecked. A field read out of an
upstream file does the same, and looks more authoritative for it.
