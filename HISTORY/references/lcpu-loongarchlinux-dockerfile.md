# lcpu-club/loongarchlinux-dockerfile

The existing `loong64` Arch image. Read because policy 11 requires mining a
reference before writing anything, and policy 8 forbids bootstrapping from an
image it publishes. Studied before any `loong64` file was written here.

## Provenance

| item | value |
| --- | --- |
| repository | `https://github.com/lcpu-club/loongarchlinux-dockerfile` |
| commit read | `f387d9ae631777fc297daab85690fe52ea69990e` |
| commit date | 2024-10-19 |
| commit subject | `feat: use loongarch lcpu` |
| clone depth | 50, which reaches the first commit in the log |
| licence | **GPL-3.0**, `LICENSE`, 674 lines. The API reports the same |
| tracker read | **0 items**, no issues and no pull requests |
| stars, forks, archived | 1, 0, not archived |
| last push | 2024-10-19 |
| sibling | `lcpu-club/loongarchlinux-docker`, same last push, also GPL-3.0. The README and the image labels name that one |
| studied on | 2026-08-28 |

```bash
git clone --depth 50 -q https://github.com/lcpu-club/loongarchlinux-dockerfile.git
git -C loongarchlinux-dockerfile rev-parse HEAD
gh api 'repos/lcpu-club/loongarchlinux-dockerfile/issues?state=all&per_page=100' --jq 'length'
```

⚠ **The tracker is empty, so there are no decisions recorded in it.** Closed
issues are usually where the reasoning is. Here there are none, and everything
below is read from the code.

## Verdict: refused, and an anti-pattern exhibit

⛔ **Refused for vendoring, on the licence.** It is GPL-3.0 and this repository
is MIT, `LICENSE:1`, holders Stefan Agner 2020 onward. Nothing from that tree
can be copied into this one. That settles it before any technical question.

⛔ **Refused as a base image, on policy 8.** Its published image is a prebuilt
artefact this repository cannot rebuild from source, and `loong64.md` shows the
root can be built from packages instead.

⭐ **It confirms two facts, and that is what it is worth.** Both were measured
here independently first, and agreeing with a second source is worth recording.

## What it confirms

### The OCI architecture is `loong64`

The published image's config blob:

```bash
img=loongarchlinux/archlinux
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:$img:pull&service=ghcr.io" | jq -r .token)
curl -sL -H "Authorization: Bearer $TOKEN" "https://ghcr.io/v2/$img/blobs/sha256:fb0dedbfb41d5a1baea25fbc3a8a0af8f05281ea325173417e75c1c40f0bb6cf" |
  jq -r '"architecture=\(.architecture) os=\(.os) created=\(.created)"'
```

`architecture=loong64 os=linux created=2025-09-04T03:35:42Z`.

⭐ Same spelling this repository's own probe produced. `loong64.md` has that
measurement.

| registry | tags |
| --- | --- |
| `ghcr.io/loongarchlinux/archlinux` | 6, including `latest` |
| `ghcr.io/lcpu-club/archlinux` | 3: `latest`, `base`, `base-devel` |

⚠ The published image is dated 2025-09-04 and the last commit is 2024-10-19, so
a build ran after the last source change. Both dates are stated rather than
characterised.

### A sixth mirror endpoint

`rootfs/etc/pacman.d/mirrorlist` carries exactly one line:

```
Server = https://mirrors.pku.edu.cn/loongarch-lcpu/archlinux/$repo/os/$arch
```

⚠ That path is `loongarch-lcpu`, not the `loongarch` this repository probed. It
is the sixth endpoint, and `pacman-mirrorlist-loong64` names it too.

## Why nothing here transfers

### It builds on a `loong64` host, which is the whole difference

`scripts/make-rootfs.sh` runs the transaction through `fakechroot -- fakeroot`
against the **build host's** pacman trust store, then `chroot`s into the result:

```bash
$WRAPPER -- pacman -Sy -r "$BUILDDIR" --noconfirm --dbpath "$BUILDDIR/var/lib/pacman" \
    --config pacman.conf --noscriptlet --hookdir "$BUILDDIR/alpm-hooks/..." base "$GROUP"
$WRAPPER -- chroot "$BUILDDIR" pacman-key --init
$WRAPPER -- chroot "$BUILDDIR" pacman-key --populate
```

⛔ **There is no keyring step at all.** The host already trusts the `loong64`
signing keys, because the host is a `loong64` Arch machine. `.drone.yml` runs
the whole pipeline in `loongcr.lcpu.dev/lcpu/archlinux:base` and `make-rootfs.sh`
takes its `pacman.conf` from `/usr/share/devtools/pacman.conf.d/`, which is the
host's devtools package.

⭐ **That is exactly the problem this repository has to solve and it does not.**
This repository builds `loong64` from an `amd64` runner, so the trust root has
to be established on a host that does not have it. `loong64.md` measures that
route: fetch the keyring against a pinned sha256, install it, populate, and run
the transaction with `SigLevel = Required`. Their approach cannot be copied
because the premise differs, licence aside.

### The bootstrap is circular by this repository's standard

`Dockerfile.template`:

```
FROM loongcr.lcpu.dev/lcpu/archlinux AS verify
```

⛔ The image is built starting from an image the same project publishes.
`tests/static/10-bootstrap-not-circular.sh` fails on that shape, and it is the
defect this repository fixed in itself. Its history is in
[`fwcd-docker-archlinux.md`](fwcd-docker-archlinux.md), finding 1.

⚠ The comment directly above that line is inherited from
`archlinux/archlinux-docker`, where the `FROM` names `docker.io/library/archlinux`.
It says the project avoids using its own image. The line below it names the
project's own registry, so the comment and the code disagree at this commit.
Stated as a measurement, since a reader of that file would otherwise trust the
comment.

### It carries the full `NoExtract` set

`pacman-conf.d-noextract.conf` holds 12 `NoExtract` lines covering man pages,
info pages, documentation, locales and `usr/share/i18n`.

⛔ Decision 5 removed every one of those from this repository after a consumer
broke, measured in `HISTORY/noextract-reverted.md`.
`tests/static/80-docs-claims.sh` fails on any rule in any shipped `pacman.conf`.
This is the same upstream set already documented in
[`archlinux-docker.md`](archlinux-docker.md), so it adds nothing new beyond
appearing in one more place.

### One mirror

The shipped list has a single `Server` line. This repository's floor is
enforced: `scripts/gen-mirrorlist` refuses a list below `MIN_SERVERS` and
`tests/static/40-mirrors-reachable.sh` requires at least two reachable.

## Mechanisms already studied elsewhere

`--noscriptlet`, alpm hooks symlinked to `/dev/null`, the `exclude` list for the
tar, `systemd-sysusers`, and the `sed -i -e 's/^root::/root:!:/'` that locks the
root account against CVE-2019-5021 all come from `archlinux/archlinux-docker`
unchanged, at `scripts/make-rootfs.sh:39` here against `:75` there. They are
covered in [`archlinux-docker.md`](archlinux-docker.md) and are not re-derived.

## What this repository takes

⛔ **No code, and no image.** Two facts are confirmed, the OCI architecture
string and a sixth mirror endpoint, and both were already measured here.
