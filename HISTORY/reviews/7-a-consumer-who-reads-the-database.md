# Review 7: a consumer who reads the package database

**The lens.** Not a consumer who runs the image, but one whose tooling asks
pacman what is installed and then acts on the answer. `pacman -Ql`, `pacman -Qo`,
`pacman -Qi`, the files under `/var/lib/pacman/local`. Where else does this image
tell that consumer something that is not true?

⚠ **This lens is chosen because it already fired once.** A downstream build read
a package's file list, checked each path, and failed. That is
`HISTORY/noextract-reverted.md`. The question here is what **else** of that shape
survives.

---

## The one that fired, and its current state

```bash
podman run --rm --platform linux/amd64 docker.io/pkgforge/archlinux:latest bash -c '
  pacman -Sy --noconfirm --needed qt6-base >/dev/null 2>&1
  echo "listed : $(pacman -Qlq | wc -l)"
  echo "missing: $(pacman -Qlq | while read -r p; do [ -e "$p" ] || printf x; done | wc -c)"'
```

```
listed : 49035
missing: 1
```

The one is `/var/lock`, a symlink to `../run/lock`. Fixed and guarded:
`tests/static/80-docs-claims.sh` fails on any `NoExtract` line in any shipped
config.

## Finding 1: `/var/lock` is still a lie, and it is not ours

`pacman -Qo /var/lock` says the `filesystem` package owns it. The path does not
resolve, because `/run/lock` is created by systemd and there is no systemd here.

```bash
podman run --rm docker.io/library/archlinux:latest sh -c 'readlink -f /var/lock; ls -ld /run/lock'
```

⭐ **Upstream's own image behaves identically.** It is a property of running Arch
without systemd, not of this build. ⚠ Left alone deliberately: creating
`/run/lock` here would diverge from every other Arch container for one dangling
symlink, and a consumer that cares can create it.

## Finding 2: the database is complete but the caches are not

This is the same class and it survives.

```bash
podman run --rm --platform linux/amd64 docker.io/pkgforge/archlinux:latest sh -c '
  ls /var/lib/pacman/sync/ | wc -l
  ls /var/cache/pacman/pkg/ | wc -l
  ldconfig -p 2>/dev/null | wc -l'
```

The sync databases are removed at build time and the package cache is emptied by
a hook. ⭐ **Both are correct and both are recoverable**: `pacman -Sy` restores
one and any install repopulates the other. A consumer that runs `pacman -Q`
against a fresh container without `-Sy` sees the local database, which is intact.

⚠ **What is not guarded**: nothing asserted the local database is readable and
complete, independently of the tool that reads it. `scripts/gen-evidence` dies
loudly when it cannot read `/var/lib/pacman/local`, so an unreadable database is
caught. A **partially** parsed one was not: `gen-evidence` walks the `desc` files
by hand with awk, and a parsing fault would drop entries into an evidence file
that still looked well formed.

⛔ **The obvious check would have been theatre.** Comparing the evidence's
`package_count` against `.packages | length` proves nothing, because
`scripts/gen-evidence:289` derives the first from the second:

```
| .package_count = (.packages | length)
```

⭐ **Fixed with a check that is not circular.** `tests/image/40-evidence.sh` now
asks pacman inside the image how many packages it has and compares that:

```
ok 12 - the evidence records all 137 packages the image reports installed
```

Seen to fail against an evidence file with one package removed:

```
not ok 12 - the evidence records every package the image reports installed
#   the image says 137, the evidence records 136
```

## Finding 3: `pacman -Qi` reports an install date that is the build date

Every package reports the same `Install Date`, the moment the image was built.
That is true rather than false, and it is worth knowing: a consumer using install
date to work out what was added on top of the base image gets one timestamp for
the whole base. ⚠ Recorded, not changed. There is no honest alternative.

## Finding 4: the evidence file and the database can drift, and one is checked

`scripts/gen-evidence` reads the installed set from the image's own database, so
they agree at build time. The evidence file is then published as a CI artifact
while the image goes to a registry. Nothing re-checks them afterwards.

⚠ **Bounded, not eliminated.** `tests/image/40-evidence.sh` runs against the
built image before publishing and asserts the evidence's digest and platform
match the image under test, so a mismatched pair cannot be published together.
What is unguarded is somebody pairing a published image with an evidence file
from a different run, which no test here can prevent.

## What this review did NOT look at

- `pacman -Qk`, the file-integrity check. It compares sizes and modes for every
  installed file and would be the strongest form of this lens. Not run: it needs
  the sync databases and a network fetch per package.
- Package scriptlets. `pacstrap-docker` does not pass `--noscriptlet`, so they
  run at build time; what they leave behind was not audited.
- `/var/lib/pacman/local` permissions and ownership.
- Anything about signatures. That is review 2's lens and was not repeated.

## Change summary

| | |
| --- | --- |
| files touched | 3 |
| lines added | 24 |
| lines removed | 0 |

`tests/image/40-evidence.sh` gained one assertion, comparing the recorded set
against what the image reports. `HISTORY/tests-seen-to-fail.md` gained its fault.
This file.
