# The evidence race, and how it was removed

⭐ **Decided 2026-08-28.** The evidence resolves against the databases the build
used. They are exported from the build rather than fetched a second time.

## What failed

The scheduled run on 2026-08-27 published nothing.

```bash
gh run view 33094128354 --json jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'
```

| job | conclusion |
| --- | --- |
| Resolve inputs | success |
| Build armv7 | success |
| Build arm64 | success |
| Build riscv64 | success |
| Build amd64 | failure |
| Create tags | skipped |

`Build amd64` failed in `Record the evidence for what was pushed`:

```
gen-evidence: these installed packages are in no repository database:
  ca-certificates-mozilla 3.127-1
gen-evidence: the databases moved between the build and this run, so the evidence has holes
```

⚠ **The topology worked.** The merge job needs the whole matrix, so one
architecture failing meant no tag moved. The defect is upstream of that.

## The window, measured

```bash
gh api repos/pkgforge-dev/docker-archlinux/actions/runs/33094128354/jobs \
  --jq '.jobs[] | select(.name=="Build amd64") | .steps[]
        | "\(.number) \(.name) \(.started_at) -> \(.completed_at) \(.conclusion)"'
```

| step | from | to |
| --- | --- | --- |
| Build and push by digest | 16:37:48Z | 16:38:37Z |
| Record the evidence for what was pushed | 16:38:37Z | 16:38:52Z |

The run log timestamps the second read:

```
2026-08-27T16:38:50.3Z     137 packages installed
2026-08-27T16:38:51.2Z     core database read
2026-08-27T16:38:52.7Z     extra database read
```

The build's own `pacman -Sy` runs inside the first step, so at most **63
seconds** separate the two reads of `core.db`. `ca-certificates-mozilla` moved
inside that window. `core` carries `3.128-1` now:

```bash
curl -sSfL --connect-timeout 10 --max-time 300 \
  -o core.db https://geo.mirror.pkgbuild.com/core/os/x86_64/core.db
tar -tzf core.db | awk 'index($0, "ca-certificates-mozilla")'
```

⭐ **The window is not the interesting number, its existence is.** It is the
whole build plus the push plus the pull, so it grows with every architecture
that gets slower and with every retry. riscv64 builds under emulation.

## The check stays

⛔ Evidence with a hole in it is what standing policy 8 forbids. A build that
publishes an image whose provenance cannot be stated is worse than one that
fails. Nothing here relaxes the check. What changes is the input it reads.

## The three options

| option | verdict |
| --- | --- |
| resolve against the database snapshot the build used | ⭐ taken |
| read what the local database has, repository lookup best effort | refused |
| retry against `archive.archlinux.org` | refused |

### Refused: the local database does not carry the missing facts

The evidence records five things per package. Three come from the image's own
database and two do not.

```bash
podman run --rm --platform linux/amd64 localhost/archlinux:amd64 \
  sh -c 'cat /var/lib/pacman/local/bash-*/desc' | awk '/^%/ { print }'
```

```
%NAME% %VERSION% %BASE% %DESC% %URL% %ARCH% %BUILDDATE% %INSTALLDATE%
%PACKAGER% %SIZE% %REASON% %LICENSE% %VALIDATION% %DEPENDS% %OPTDEPENDS%
%PROVIDES% %XDATA%
```

There is no `%CSIZE%` and no `%SHA256SUM%`. A package resolved this way carries
a dash for its size and its checksum, and `tests/image/40-evidence.sh` names
any entry that does, which is the assertion that makes the file evidence. The
option amounts to deleting that assertion for whichever package lost the race.

### Refused: an archive exists for one port of four

```bash
for u in https://archive.archlinux.org/ https://archive.archlinuxarm.org/ \
         https://archive.archriscv.felixc.at/; do
  printf '%-40s %s\n' "$u" \
    "$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "$u")"
done
```

Measured 2026-08-28:

| host | result |
| --- | --- |
| `archive.archlinux.org` | 200 |
| `archive.archlinuxarm.org` | does not resolve |
| `archive.archriscv.felixc.at` | does not resolve |

No server in `rootfs/arm64`, `rootfs/armv7` or `rootfs/riscv64` names an archive
either. A fix for amd64 alone leaves the same failure on the three ports that
are slowest to build and so hold the window open longest.

## What was built

### The Dockerfile keeps what pacstrap resolved against

The bootstrap stage copies the synced databases out before the step that empties
the directory, and a `dbsnapshot` stage carries them.

⛔ **The order is the mechanism.** After the delete the copy exports an empty
directory, and every other check in the tree stays green.
`tests/static/68-evidence-snapshot.sh` compares the two line numbers.

⭐ **The image is untouched.** Nothing in the image stage depends on
`dbsnapshot`, so an ordinary build never materialises it:

```bash
podman build --platform linux/amd64 --build-arg "IMAGE_VERSION=$(date -u +%Y.%m.%d)" \
  --build-arg "SOURCE_COMMIT=$(git rev-parse HEAD)" \
  --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -t localhost/archlinux:amd64 . \
  | awk 'index($0, "STEP 1/")'
```

That prints `[1/3] STEP 1/14` and `[3/3] STEP 1/19`. There is no `[2/3]`.

⭐ **The image carries nothing new, measured rather than reasoned about.** The
same tree was built twice on `linux/amd64`, once from the Dockerfile at
`7c0c42b` and once from this one, sharing the layer cache so both install the
same package set:

```bash
git show HEAD~1:Dockerfile > Dockerfile.pre
podman build -f Dockerfile.pre --platform linux/amd64 [the same three build args] -t localhost/archlinux:pre .
for t in amd64 pre; do
  podman run --rm --platform linux/amd64 "localhost/archlinux:$t" sh -c 'find / -xdev | LC_ALL=C sort' > "files-$t.txt"
  podman run --rm --platform linux/amd64 "localhost/archlinux:$t" sh -c 'pacman -Q | LC_ALL=C sort' > "pkgs-$t.txt"
done
diff files-amd64.txt files-pre.txt
diff pkgs-amd64.txt pkgs-pre.txt
```

Both diffs are empty: 33086 paths and 137 packages either way.

### gen-evidence reads them where the build left them

`DB_SNAPSHOT` names the directory. Set, the databases are read from it and
nothing is fetched. Unset, they are fetched, which is the local path and still
carries the race.

⛔ **Validated before the image is run**, so a wrong path is reported in under a
second rather than after a pull. That is also what lets the static suite drive
the refusals with no runtime and no network.

### The build job exports it

The export is a second `docker/build-push-action` on the same pinned digest,
with `target: dbsnapshot` and `outputs: type=local,dest=/tmp/dbsnapshot`. The
bootstrap stage is already in the builder from the step above, so it exports
files rather than installing anything again.

## Measurements

Built 2026-08-28 on `linux/amd64`, from the tree this document ships in.

| what | value |
| --- | --- |
| `core.db` exported | 130051 bytes |
| `extra.db` exported | 8894888 bytes |
| packages recorded | 137 |
| package table from the snapshot against the table from the mirrors | identical |

```bash
podman build --platform linux/amd64 --target dbsnapshot \
  --build-arg "IMAGE_VERSION=$(date -u +%Y.%m.%d)" -t localhost/dbsnap:amd64 .
cid="$(podman create localhost/dbsnap:amd64 true)"
podman export "$cid" | tar -x -C dbsnap
podman rm -f "$cid"
```

⚠ `podman build --output` is not supported against a remote machine, which is
what a Windows host has, so the export goes through a container there. CI uses
`--output type=local` directly.

```bash
DB_SNAPSHOT="$PWD/dbsnap" scripts/gen-evidence amd64 localhost/archlinux:amd64 linux/amd64 ev-snap.json
scripts/gen-evidence amd64 localhost/archlinux:amd64 linux/amd64 ev-fetch.json
diff <(jq -S '.packages' ev-snap.json) <(jq -S '.packages' ev-fetch.json)
```

The diff is empty. With no race in flight the two paths agree exactly, which is
what makes the snapshot a replacement rather than a different answer.

## The run that proves it

Dry run `33162764880`, 2026-08-28, on branch `evidence-race`. All six jobs
succeeded, including `Create tags`.

```bash
gh run view 33162764880 --json status,conclusion,jobs \
  --jq '"run: \(.status)/\(.conclusion)", (.jobs[] | "\(.name) \(.status)/\(.conclusion)")'
```

⭐ **Every enabled repository on every architecture was read from the export,
and nothing was fetched.**

```bash
gh run view 33162764880 --log | grep "database read from"
```

| architecture | databases read from `/tmp/dbsnapshot` |
| --- | --- |
| amd64 | `core`, `extra` |
| arm64 | `core`, `extra`, `alarm`, `aur` |
| armv7 | `core`, `extra`, `alarm`, `aur` |
| riscv64 | `core`, `extra` |

⚠ The two ARM ports enable four repositories, not two. The Dockerfile copies
`*.db`, so it generalises without naming any of them. Nothing in the export
knows how many repositories an architecture has.

The export costs one to two seconds, because every layer it needs is already in
the builder:

```bash
gh api repos/pkgforge-dev/docker-archlinux/actions/runs/33162764880/jobs \
  --jq '.jobs[] | select(.name | startswith("Build"))
        | .name + " " + (.steps[] | select(.name | startswith("Export the databases"))
        | "\(.started_at) -> \(.completed_at) \(.conclusion)")'
```

| architecture | export step |
| --- | --- |
| amd64 | 10:20:01Z to 10:20:02Z |
| armv7 | 10:21:48Z to 10:21:50Z |
| arm64 | 10:22:22Z to 10:22:24Z |
| riscv64 | 10:22:36Z to 10:22:38Z |

Its log shows `CACHED` on every layer of the bootstrap stage and one
`importing cache manifest` line.

⚠ **The evidence step did not get faster.** It ran 14 seconds on amd64 against
15 seconds on the run that failed. Reading `extra.db` locally replaces fetching
8.9 MB, and the export adds a second back. The point is correctness, not speed.

## What this does not fix

⚠ **A cache miss on the export.** The exported databases are the ones the image
was installed from only when the export hits the layer cache the build filled.
Nothing in the tree can check that. What happens on a miss is the old behaviour:
gen-evidence still names every package it cannot account for, and the run fails
rather than passing quietly. The diagnostic distinguishes the two causes, because
a snapshot that has a hole did not come from this build, and telling the reader
that upstream moved would send them to the wrong place.

⚠ **The four architectures still resolve at four different times.** Each build
job runs its own `pacman -Sy`, so one run is four package sets rather than one.
This changes nothing about that. It is the same problem as the shared package
cache in the work list.

⚠ **Nothing is measured about how often the race fires.** One run is known to
have lost to it. Whether the earlier green runs were lucky or the window was
shorter is not recorded anywhere.

## What is checked by a test

| claim | test |
| --- | --- |
| the Dockerfile has a `dbsnapshot` stage, taking content from the bootstrap stage | `tests/static/68-evidence-snapshot.sh` 1, 2 |
| the databases are copied out before the directory is emptied | `68` 3 |
| the build job exports the target, and reads it back from the same path | `68` 4, 5 |
| a `DB_SNAPSHOT` that cannot be used is refused, and named | `68` 6, 7 |
| a usable one is accepted | `68` 8 |
| the evidence is refused when a package cannot be accounted for | `scripts/gen-evidence`, and `tests/image/40-evidence.sh` on the file it writes |

Every one of those was seen to fail. `HISTORY/tests-seen-to-fail.md`.
