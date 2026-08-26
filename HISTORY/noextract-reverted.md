# NoExtract, and why there is none

⛔ **A downstream consumer broke.** For one build, this image stripped
documentation, info pages, gtk-doc and every locale through `NoExtract`. Every
rule is now gone, man pages included, so the package database and the filesystem
agree.

## The report

`Samueru-sama/Anylinux-AppImages`, one of the named consumers, failed with:

```
/usr/share/doc/qt6/global/template/images/Qt-logo.png is NOT a valid path!
```

The path is in the `qt6-base` package. Their tooling walks a package's file list
and checks each path exists.

## Reproduced

```bash
podman run --rm --platform linux/amd64 docker.io/pkgforge/archlinux:latest bash -c '
  pacman -Sy --noconfirm --needed qt6-base >/dev/null 2>&1
  pacman -Qlq qt6-base | grep -c "^/usr/share/doc/"
  ls -l /usr/share/doc/qt6/global/template/images/Qt-logo.png'
```

```
167
ls: cannot access '/usr/share/doc/qt6/global/template/images/Qt-logo.png': No such file or directory
```

⭐ **The database and the filesystem disagreed.** `pacman -Qlq` listed 167 paths
under `/usr/share/doc/` for that one package, and none of them were on disk.
`NoExtract` governs what is written; it does not change what the package
database records.

## The scale, which the symptom understated

Same image, `base` plus `qt6-base`, every path the database claims, checked:

```bash
pacman -Qlq | while read -r p; do [ -e "$p" ] || printf '%s\n' "$p"; done
```

| | paths |
| --- | --- |
| database lists | 49035 |
| missing on disk | 25513 |

By prefix:

| prefix | missing |
| --- | --- |
| `usr/share/man` | 18944 |
| `usr/share/locale` | 4539 |
| `usr/share/doc` | 1022 |
| `usr/share/i18n` | 563 |
| `usr/share/X11` | 236 |
| `usr/share/info` | 135 |
| `usr/share/gtk-doc` | 68 |

⚠ 52% of every path pacman claimed was absent. Fixing only `usr/share/doc` would
have left 24491 of them.

## What was a regression, measured against the image that preceded the rebuild

`ghcr.io/pkgforge-dev/archlinux:v2026.05.15`, the newest tag published before the
rebuild:

```bash
podman run --rm --platform linux/amd64 ghcr.io/pkgforge-dev/archlinux:v2026.05.15 bash -c '
  for d in /usr/share/doc /usr/share/man /usr/share/info /usr/share/gtk-doc \
           /usr/share/help /usr/share/locale /usr/share/i18n /usr/share/X11/locale; do
    [ -d "$d" ] && echo "$d present $(find "$d" -type f | wc -l) $(du -sh "$d" | cut -f1)" || echo "$d ABSENT"
  done'
```

| path | before the rebuild | after it | verdict |
| --- | --- | --- | --- |
| `usr/share/doc` | present, 545 files, 13M | absent | ⛔ regression |
| `usr/share/info` | present, 104 files, 7.3M | absent | ⛔ regression |
| `usr/share/gtk-doc` | present, 43 files, 284K | absent | ⛔ regression |
| `usr/share/locale` | present, 1494 files, 109M | stripped | ⛔ regression |
| `usr/share/i18n` | present, 604 files, 17M | stripped | ⛔ regression |
| `usr/share/man` | ABSENT | absent | unchanged |
| `usr/share/help` | ABSENT | absent | unchanged |
| `usr/share/X11/locale` | ABSENT | absent | unchanged |

⭐ **Man pages were already gone.** The image before the rebuild deleted
`/usr/share/man` with a PostTransaction hook, `rootfs/any/usr/share/libalpm/hooks/man-page-remove.hook`
at commit `9d1e142`, which re-ran on the consumer's next transaction. Everything
else on that list is a change this project introduced.

## What is in the tree now

No `NoExtract` rule at all, in any `rootfs/<arch>/etc/pacman.conf`.

```bash
grep -n '^NoExtract' rootfs/*/etc/pacman.conf
```

Exit status 1. Only the stock commented `#NoExtract   =` default remains.

⭐ **The first fix kept `usr/share/man/*`**, on the grounds that man pages had
been absent for years and so were not a regression. The maintainer ruled that
the database and the filesystem should agree completely, which meant that rule
going too.

⚠ One more removal was found while checking the result.
`rootfs/any/etc/pacman.d/hooks/package-cleanup.hook` ran
`rm -rf /var/cache/pacman/pkg`, which deletes a directory the `pacman` package
owns. It now runs `find /var/cache/pacman/pkg -mindepth 1 -delete`, which empties
it and leaves the directory. Dropping the cached packages is still a sane
default: they come back on demand.

## Verified

Built from this tree and checked against the report:

```bash
podman run --rm --platform linux/amd64 localhost/archlinux:final bash -c '
  pacman -Sy --noconfirm --needed qt6-base >/dev/null 2>&1
  ls -l /usr/share/doc/qt6/global/template/images/Qt-logo.png
  pacman -Qlq | while read -r p; do [ -e "$p" ] || printf %s\n "$p"; done'
```

```
-rw-r--r-- 1 root root 2425 Aug 20 07:47 /usr/share/doc/qt6/global/template/images/Qt-logo.png
/var/lock
```

| | published, stripped | first fix, man only | now |
| --- | --- | --- | --- |
| database lists | 49035 | 49035 | 49035 |
| missing on disk | 25513 | 18946 | **1** |

⭐ **The one remaining is `/var/lock`**, a symlink to `../run/lock` owned by the
`filesystem` package. `/run/lock` is created by systemd, so in a container the
link dangles. `docker.io/library/archlinux:latest` behaves the same way. It is
not something this image withholds.

A locale needs no preparation:

```bash
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen
locale -a
```

```
C C.utf8 de_DE.utf8 en_US.utf8 POSIX
```

`tests/run.sh image` passes 30 of 30 against the rebuilt image, and
`tests/static/80-docs-claims.sh` assertion 9 now fails on any `NoExtract` line in
any shipped config.

## What this costs

```bash
podman image inspect <ref> --format '{{.Size}}'
```

| image | size |
| --- | --- |
| `ghcr.io/pkgforge-dev/archlinux:v2026.05.15`, before the rebuild | 521 MiB |
| `docker.io/pkgforge/archlinux:latest`, everything stripped | 395 MiB |
| this tree, nothing stripped | 543 MiB |

⚠ 543 MiB is 22 MiB above what consumers had before the rebuild, because man
pages are now extracted too, and 148 MiB above the stripped build.

⭐ **The bar was never size.** It is whether a consumer could undo the change,
and the answer turned out to be no in the way that mattered: they could restore
the files, but not before their build had already failed on a path the package
database said was there.

## The same complaint exists upstream, and still applies to their image

`archlinux/archlinux-docker` issue 55, `Suggestion: restore excluded files in
base image and provide a slim variant`, opened 2020-12-06 and still open. The
reporter quotes that project's own stated principle back at it:

> All installed packages have to be kept unmodified

The official image still behaves that way:

```bash
podman run --rm --platform linux/amd64 docker.io/library/archlinux:latest bash -c \
  'pacman -Qlq | while read -r p; do [ -e "$p" ] || printf %s\n "$p"; done | head -8'
```

```
/usr/share/doc/
/usr/share/doc/acl/
/usr/share/doc/acl/CHANGES
/usr/share/doc/acl/COPYING
/usr/share/doc/acl/COPYING.LGPL
/usr/share/doc/acl/extensions.txt
/usr/share/doc/acl/libacl.txt
/usr/share/locale/de/
```

Recorded in `HISTORY/references/archlinux-docker.md`. It was read before this
incident and treated as cost evidence about somebody else's decision.
