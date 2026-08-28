# Review 20: a reference adopted on one reading

**Lens.** A policy 11 verdict is one word and it travels. Later sessions read
"adopt" and skip the qualifications under it. This review asks what the adopt
verdict on `Aseem0xff/pacman-static` actually commits this repository to, what
would have to be false for it to be wrong, and whether the write-up says enough
that a session acting on it would find out.

**Date.** 2026-08-28, against `756bef1`.

⚠ Distinct from review 17, which asked whether an unverified report was safe to
leave in the record. That was about a claim nobody had checked. This is about
what happens after it is checked and a verdict is written down.

---

## What was opened

- `HISTORY/references/aseem-pacman-static.md`, whole, the file under review.
- `HISTORY/references/methodology-template.md`, 117 lines, for what a verdict is
  supposed to carry.
- `HISTORY/references/lcpu-loongarchlinux-dockerfile.md`, the most recent
  previous reference, for the house shape and for how a refusal is stated.
- `HISTORY/CONTINUE.md` standing policy 11 and decision 7, re-read rather
  than recalled.
- The reference tree at `38f7e3e45730f9a6dd4d62675dc1e9594b90f4e4`, for the four
  `PKGBUILD` lines and the licence files the verdict rests on.

## Finding 1: the verdict is doing two jobs and the document separates them

⭐ **"Adopt" here does not mean vendor.** The document says so in the sentence
after the verdict: adoption is of the method and the file level detail, each to
be re-measured, and nothing has been built or run here. That distinction is the
one a later reader is most likely to lose.

⚠ **The verdict vocabulary makes this harder than it needs to be.** Policy 11
offers adopt, confirms, anti-pattern exhibit, filed elsewhere, refused. Only
`adopt` fits a reference whose recipe this project intends to build from, and
the same word covers vendoring a file verbatim. ⛔ Nothing in the vocabulary
distinguishes them, so the distinction has to live in prose every time and can
be dropped every time.

## Finding 2: what would have to be false

Ranked by what it costs if it is wrong.

| if this is false | what breaks | how a session would find out |
| --- | --- | --- |
| ⛔ **`zig cc` produces a correct binary, not merely a linking one** | the whole method. Every non `x86_64` claim is `qemu-user`, which passes syscalls to the host kernel and does not exercise the target's page size | only real hardware, or a defect. ⚠ Nothing planned here would surface it |
| ⛔ **the intermittent `SIGSEGV` is not in the binary** | a bootstrap tool whose exit status cannot be trusted. 3 in 50, always under load, moving between architectures | its own `TASKS.md` T-08 step 4: run an Arch built `pacman-static` on the same host |
| the 0BSD licence is what it says | the copying permission. ⭐ Checked: `LICENSE` is the full text and the API agrees | already checked, twice, two ways |
| the `$CARCH` defect is real | one paragraph of the write-up, not the verdict | ⭐ already checked against live upstream, not the corpus |

⭐ **The two that matter are both marked in the document** and both are marked
as unresolved rather than as caveats. ⚠ Neither has an owner or a next step in
this repository, because TODO 2 has not started.

## Finding 3: the gap the write-up names and does not close

⛔ **`armv7` is not covered.** Four of this repository's five architectures are
in the reference; the fifth is not, and neither `PKGBUILD` reference builds it
in a form known to work. That single fact decides whether TODO 2 shrinks or
merely changes shape, because a static `pacman` for four of five architectures
does not remove the trust root, it removes it for four fifths of the matrix.

⚠ **As written, the document stated this and did not weigh it.** It appeared
once, under "What it does not settle". ⭐ For a task whose whole purpose is to
remove one trust root, an architecture that keeps it is the finding, not a
footnote. It is now in the verdict section as well, sized against five
architectures rather than four, so this finding is closed against the file as it
stands at `333` lines.

## Finding 4: the tracker step yielded nothing, and that is a real gap

Policy 11 puts the tracker ahead of the code and says closed issues are where
the decisions are. Here:

```bash
gh api 'repos/Aseem0xff/pacman-static/issues?state=all&per_page=100' --paginate --jq 'length'
gh api 'repos/Aseem0xff/pacman-static/pulls?state=all&per_page=100' --paginate --jq 'length'
```

Both `0`. The repository was created 2026-08-28T10:40:45Z, hours before it was
read, and carries one commit.

⭐ **The write-up records this as a gap rather than as a clean result**, which is
the right call: a one day old repository has had no chance to be argued with.
⚠ **The comparison that would have substituted for a tracker was not made.** The
reference's own claims about `aur/pacman-static` and about `mussel` could each
have been checked against **those** projects' trackers, which are years old.
`mussel#29`, `#57`, `#2` and `#54` are quoted in the reference and none was
opened here.

## Finding 5: one internal inconsistency was found, and the class matters more

`experiments/80-build-pacman.sh:91` states as fact a cause that `RESEARCH.md`
§0 claim 1 and §4.3 both retract.

⭐ **The write-up records it as a pattern rather than a complaint**, and the
pattern is the useful part: a retraction that reaches the write-up and not the
code leaves the wrong answer where the next reader works. ⚠ **This repository
has the same shape open right now**, in TODO 10: two comments about `NoExtract`
that decision 5 superseded. Found in a reference, present here.

## What was fixed, and where the rest is tracked

| finding | outcome |
| --- | --- |
| 1, `adopt` covers two different things | ⭐ **partly fixed.** The write-up now says outright that adopt does not mean vendor. Changing policy 11's vocabulary is the maintainer's and is not proposed |
| 2, the two claims that would sink the method | **not fixed and not fixable here.** Real hardware and the open `SIGSEGV` are both in the reference's own `TASKS.md`. TODO 2 is where they land when it starts |
| 3, `armv7` is uncovered and under-weighted | ⭐ **fixed, in the repository.** The write-up's verdict section now carries it, sized as four fifths of the matrix rather than as a footnote. TODO 2 carries it too, but that file is scratch |
| 4, the tracker yielded nothing and no substitute was read | **not fixed.** The four `mussel` issues and the AUR thread are named in the write-up's "what the fetches did not get" |
| 5, a retraction that did not reach the code | **not fixed there**, and it is not this repository's file. ⭐ The same shape here is TODO 10, two `NoExtract` comments decision 5 superseded |

## What was ruled out

- **The verdict being decided by the maintainer's report.** The document's
  measurements are all independent of it, and three were taken against live
  upstream rather than against the reference's own corpus.
- **Decision 7 being quietly overturned.** Read again: it refuses vendoring
  `packages-core-pacman-static` and requires this project's own recipe. The
  write-up says nothing measured overturns it, and puts the one question it
  raises, whether the canonical AUR package replaces the fork as the studied
  reference, to the maintainer rather than answering it.
- **A number that cannot be reproduced.** Every figure in the write-up carries
  its command. The corpus size was re-measured because the reference's own
  README disagreed with it, 10.4 MB against a claimed 59 MB.
- **Overstating the licence.** The document says twice that 0BSD on the recipe
  does not change that the binary is `GPL-2.0-or-later`, and that the source
  offer obligation is unchanged.

## ⚠ What this did not look at

- ⛔ **Whether adopt is the right verdict.** This review checked what the verdict
  commits to and whether the document supports it. It did not re-derive the
  verdict, and it did not build anything.
- **The parts of the reference nobody has opened.** `scripts/mine-repo.sh`, the
  four `examples/`, eleven `experiments/` scripts, fifteen outputs, and the 1249
  file corpus beyond four `PKGBUILD` lines. The write-up lists these. ⭐ The
  `examples/` are the ones that matter: TODO 2 asks this repository for a
  bootstrapping guide and those are somebody's version of one.
- **The upstream trackers the reference quotes.** `mussel`, `pacman` on GitLab,
  the AUR comment thread, the Manjaro fork's GitLab tracker. None fetched, here
  or there.
- **Whether the reference will still exist.** It was pushed to four minutes
  before its commit was captured. The commit is recorded, and no copy of the
  tree is kept in this repository.

## Change summary

Files touched by the change this reviews: 1 new,
`HISTORY/references/aseem-pacman-static.md`, 312 lines. This review adds no
change of its own.
