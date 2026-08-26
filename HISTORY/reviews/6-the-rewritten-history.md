# Review 6: somebody auditing a repository with one commit

**The lens.** A reader arrives at `main`, finds a single root commit, and has to
decide whether to trust the images it builds. Everything a normal audit leans on,
who changed what and when, is gone. What can still be checked, and what silently
cannot?

⚠ **This lens exists because the rewrite created it.** No earlier review could
have used it.

---

## What was actually done

```bash
git log --oneline --all | head
git rev-list --count main
git log -1 --format='%P' main
```

| | |
| --- | --- |
| `main` | `bce16c5`, one commit, **no parent** |
| `history-archive` | `9d1e142`, the tip of the pre-rewrite history |
| tags on GHCR | 161 |
| tags on Docker Hub | 161 |

The rewrite used `git checkout --orphan`, so `main` is a root commit rather than
a squash with a hidden ancestor.

## Finding 1: the archive is a branch, and a branch can be deleted

⛔ **The single thing this whole arrangement rests on is one unprotected ref.**

```bash
gh api repos/pkgforge-dev/docker-archlinux/branches --jq '.[] | "\(.name) protected=\(.protected)"'
```

```
debug            protected=false
history-archive  protected=false
main             protected=true
template-adoption protected=false
```

`main` denies force pushes and deletions. `history-archive` denies nothing. A
`git push --delete origin history-archive` removes the only copy of everything
before the rewrite, and `main` has no ancestry that would keep those objects
reachable.

⭐ **Fixed as far as this session can fix it**: recorded in
`HISTORY/maintainer-actions.md` as an action for the repository owner, because
protecting a branch is a settings change and the brief reserves those. The commit
`9d1e1429259625323139cb39dd1c81764c73501d` is written in three tracked places,
`README.md`, `HISTORY/rewrite.md` and the commit body, so the ref can be
recreated from any clone that has it even if the branch goes.

⚠ **What that does not solve.** If no clone has it and the branch is gone, the
objects are gone. A tracked hash is a name, not a copy.

## Finding 2: the commit body makes claims the tree cannot check

The body says registries, tag families and `:latest` are unchanged and that both
registries hold 161 tags. ⭐ **True when written, and unfalsifiable from the
repository.** A reader in six months has no way to tell whether it was ever true.

⚠ Not fixed, and I do not think it should be. The alternative is a tracked file
of tag counts that goes stale every publish, which is worse. What makes the claim
checkable is that the assertion lives in a test rather than in prose:
`tests/static/60-tag-families.sh` has 24 assertions over `scripts/tag-names`, and
`tests/static/80-docs-claims.sh` checks the README's tag table against what
`tag-names` emits. The commit body is the weakest form of the claim and the tests
are the strong one.

## Finding 3: a stale branch now looks like history

`template-adoption` points at `8cf0ca69`, a commit from the discarded history. To
a reader it is indistinguishable from a live branch, and it is the only place
some of that work is reachable.

⭐ Recorded in `HISTORY/maintainer-actions.md` with `debug`. ⛔ Not deleted: the
brief reserves branch deletion to the owner, and deleting the last reference to
commits is exactly the operation that should not be done on someone's behalf.

## Finding 4: provenance survives the rewrite, and points at a commit that is gone

Every published image carries `org.opencontainers.image.revision` and a build
provenance attestation naming the commit it was built from. Images published
before the rewrite name commits that are no longer on any branch except the
archive.

```bash
docker buildx imagetools inspect docker.io/pkgforge/archlinux:v2026.05.15 --format '{{ json .Provenance }}'
```

⚠ **Not fixed and not fixable.** Those images exist and their provenance is
honest about what built them. It is a reason the archive matters: without it, a
published image's stated source commit resolves to nothing.

⭐ Images published after the rewrite name `bce16c5`, which is on `main`.

## What this review did NOT look at

- The contents of the archived history. It was preserved, not audited.
- Whether any published image can be reproduced from its recorded commit. That
  is bit-reproducibility, which this project has not attempted.
- GitHub's own retention of unreachable objects, which is not a guarantee anybody
  should rely on and was not measured.
- The `debug` branch's contents.

## Change summary

| | |
| --- | --- |
| files touched | 2 |
| lines added | 34 |
| lines removed | 0 |

`HISTORY/maintainer-actions.md` gained the branch-protection and stale-branch
items. This file.
