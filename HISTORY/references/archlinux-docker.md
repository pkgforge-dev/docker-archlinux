# archlinux/archlinux-docker

Reference study of the official Arch Linux container image build. It is the
reference implementation for exactly the problem this repository solves. Two of
its files were already cited in `Dockerfile:74` and `Dockerfile:75`; the project
itself had not been read.

## Provenance

| item | value |
| --- | --- |
| repository | `https://gitlab.archlinux.org/archlinux/archlinux-docker` |
| commit read | `34b87485162b028c8d957bdcd2674359d883cd21` |
| commit date | 2026-05-10 |
| clone depth | 1 |
| licence | ⛔ **GPL-3.0**, `LICENSE:1` |
| commit already cited here | `301942f9e5995770cb5e4dedb4fe9166afa4806d` |
| studied on | 2026-08-26 |

```bash
git clone --depth 1 -q "https://gitlab.archlinux.org/archlinux/archlinux-docker.git" archlinux-docker
git -C archlinux-docker rev-parse HEAD
head -3 archlinux-docker/LICENSE
```

## Verdict: refused for vendoring, adopt as mechanisms

⛔ **The licence settles vendoring.** `LICENSE:1` is the GNU General Public
License version 3. This repository is MIT, `LICENSE:1`. Copying its scripts here
is not available, the same conclusion as `rate-mirrors` and for a different
reason.

⭐ What transfers is a set of mechanisms, each cited at file and line, plus one
finding that changed a test in this repository.

## The existing citation resolves, and the line has since moved

`Dockerfile:75` cites `Makefile#L22` at commit `301942f9`. Checked:

```bash
curl -sS "https://gitlab.archlinux.org/archlinux/archlinux-docker/-/raw/301942f9e5995770cb5e4dedb4fe9166afa4806d/Makefile" | sed -n '22p'
```

```
	fakechroot -- fakeroot -- chroot $(BUILDDIR) sh -c 'pacman-key --init && pacman-key --populate && bash -c "rm -rf etc/pacman.d/gnupg/{openpgp-revocs.d/,private-keys-v1.d/,pubring.gpg~,gnupg.S.}*"'
```

⭐ **The citation is exact.** At `34b87485` that same `Makefile` is 26 lines and
line 22 is a comment, so the pin by commit is what keeps the citation readable.
Policy 10, demonstrated on this repository's own documentation.

## Finding 1: root's password field, and a CVE

`scripts/make-rootfs.sh:76`:

```bash
sed -i -e 's/^root::/root:!:/' "$BUILDDIR/etc/shadow"
```

The comment above it at `scripts/make-rootfs.sh:75` names CVE-2019-5021. An
empty second field in `/etc/shadow` means root authenticates with no password.

Measured against the published image:

```bash
podman run --rm --platform linux/amd64 docker.io/pkgforge/archlinux:latest bash -c 'grep "^root:" /etc/shadow; passwd -S root'
```

```
root:*:14871::::::
root L 2010-09-19 -1 -1 -1 -1
```

⭐ **The defect is absent here.** Arch's `filesystem` package ships `root:*`,
which is a locked account, and `passwd -S` agrees with `L`. The upstream `sed`
is defensive against a state this bootstrap does not produce.

⚠ **Absent is not guarded.** Nothing asserted it. It is now assertion 8 of
`tests/image/50-consumer-contract.sh`, and it has been seen to fail against an
image with `root::` injected.

## Finding 2: the archive is a pinned package source, and it is one value

`scripts/make-rootfs.sh:46`, in the `repro` build only:

```bash
sed -i "1iServer = https://archive.archlinux.org/repos/$ARCHIVE_SNAPSHOT/\$repo/os/\$arch" rootfs/etc/pacman.d/mirrorlist
```

`ARCHIVE_SNAPSHOT` is a date, `Makefile:7`, defaulting to yesterday. The line is
**prepended**, so the archive is preferred and the ordinary mirrors stay as
fallback.

⭐ **This answers a question D3 asks and gives a cheaper answer than the one it
proposes.** D3 asks whether the build can run from a pinned set of package files
whose sha256 sums live in this repository, and notes the cost: hundreds of
hashes for policy 9 to watch. Upstream pins **one date** against an immutable
archive instead. One value, one watcher.

⚠ It is not equivalent. A hash set proves the bytes; a date trusts
`archive.archlinux.org` to be immutable and reachable. It is also Arch only:
Arch Linux ARM and Arch RISC-V publish no equivalent archive, so it covers one
of this repository's four architectures.

## Finding 3: reproducibility costs the keyring, and this image cannot pay it

`REPRO.md:6`:

> Note that, to ensure reproducibility, the pacman keys are stripped from this
> image, so you're expected to run `pacman-key --init && pacman-key --populate archlinux`
> before being able to update the system and install packages via `pacman`.

The mechanism is `scripts/make-rootfs.sh:67`, `rm -rf "$BUILDDIR"/etc/pacman.d/gnupg/*`.

⛔ **This repository cannot adopt that.** The direct consumer's first operation
is a signature-verifying `pacman -Syu` against the shipped keyring, measured in
`devscripts-archlinux.md`. Stripping the keyring breaks it on its first command.

⭐ **So bit-reproducibility and a ready-to-use keyring are in tension, and
upstream ships both by publishing two images.** `repro` is reproducible, `base`
is usable. Recorded here as the input to any D3 decision, not decided.

## Finding 4: the reproducible tar options

`scripts/make-rootfs.sh:79` and `:89`:

```
--mtime="@$SOURCE_DATE_EPOCH" --clamp-mtime --sort=name
--pax-option=delete=atime,delete=ctime
--numeric-owner --xattrs --acls
```

⭐ Directly usable for D6, which proposes publishing a rootfs tarball. These are
the options that make two runs produce the same bytes.

`REPRO.md:133` gives the build side: `podman build --no-cache
--source-date-epoch=$SOURCE_DATE_EPOCH --rewrite-timestamp`.

⚠ `REPRO.md:14` states the honest limit: reproducibility assumes the same build
environment, and an older image is harder to reproduce as the environment drifts.

## Finding 5: hooks are disabled by symlinking each to /dev/null

`scripts/make-rootfs.sh:19`:

```bash
mkdir -vp "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks"
find /usr/share/libalpm/hooks -exec ln -sf /dev/null "$BUILDDIR/alpm-hooks"{} \;
```

Then `scripts/make-rootfs.sh:59` passes `--hookdir` at that directory, and
`:57` passes `--noscriptlet`.

⚠ Recorded rather than adopted. `pacstrap-docker` runs `pacman -r` against a
root with no hooks installed yet, so there is nothing to suppress at that point.

## Finding 6: the container sandbox setting, and why it does not apply here

`scripts/make-rootfs.sh:29` to `:39` set `DisableSandboxFilesystem`, or
`DisableSandbox` on older pacman, with the comment `No kernel landlock in
containerd`.

Checked against the published image:

```bash
podman run --rm --platform linux/amd64 docker.io/pkgforge/archlinux:latest bash -c 'grep -n DisableSandbox /etc/pacman.conf; grep -n DownloadUser /etc/pacman.conf; pacman --version | head -2'
```

No `DisableSandbox` line, no `DownloadUser` line, `Pacman v7.1.0`. pacman's
sandbox applies to the download user, and with no `DownloadUser` configured the
path is not taken. A full `pacman -Syu` inside the image succeeds, which is the
measurement rather than the reasoning.

⛔ **Adding `DownloadUser` later would pull this in.** Recorded so that
decision is taken with the landlock requirement known.

## Other mechanisms read and not adopted

| mechanism | source | note |
| --- | --- | --- |
| `update-ca-trust` in the chroot | `scripts/make-rootfs.sh:61` | already done here. The CA bundle defect it prevents is `tests/image/30-ca-bundle.sh`. |
| `os-release` as a symlink to `/usr/lib/os-release` | `scripts/make-rootfs.sh:42` | not adopted. This repository writes a real `/etc/os-release` with an `IMAGE_VERSION`, because no Arch port ships a `VERSION_ID`. |
| `systemd-sysusers --root /` | `scripts/make-rootfs.sh:73` | not adopted, and not measured here. |
| the tar exclude list | `exclude`, 18 lines | overlaps what this build already omits. `./etc/pacman.d/gnupg/private-keys-v1.d/*` matches the removal at `Dockerfile:75`'s cited line. |
| `renovate.json` | repository root | their pin watcher. Dependabot fills that role here, decision 2. |

## The tracker

⚠ Policy 11's `gh api` procedure does not reach GitLab. The equivalent is the
GitLab REST API, and it is anonymous for issue titles and descriptions:

```bash
B="https://gitlab.archlinux.org/api/v4/projects/archlinux%2Farchlinux-docker"
curl -sS "$B/issues_statistics" | jq -r '.statistics.counts'
curl -sS "$B/issues?state=opened&per_page=100" | jq -r '.[] | "\(.iid)\t\(.title)"'
```

79 issues, 15 open and 64 closed, read on 2026-08-26.

⛔ **Comments could not be read.** The notes endpoint refuses anonymous access:

```bash
curl -sS "$B/issues/55/notes?per_page=5"
```

```
{"message":"401 Unauthorized"}
```

So every issue below is reported from its description only. Policy 11 warns that
reading the body without the comments misreports the state, and that limit
applies to all of it.

### Issue 55, open since 2020-12-06: restore the excluded files

`Suggestion: restore excluded files in base image and provide a slim variant`.
The reporter argues the `NoExtract` exclusions make the image weaker as a
development environment, and quotes upstream's own stated principle back at it:

> All installed packages have to be kept unmodified

⭐ **It is still open after five and a half years.** That is cost evidence about
the strip decision that no amount of reading the code would give.

⛔ **Decisions 5, 6 and 7 are not reopened.** What the issue confirms is why the
mechanism matters more than the outcome: `NoExtract` is a config line a consumer
comments out, and `examples/04-add-a-locale.sh` is that undo path written down.
A build that deleted the files instead would leave the reporter with no move.

### Issue 106, open since 2025-09-08: xattrs and acls are not preserved

The reporter measures `security.capability` missing from `/usr/bin/newgidmap`,
which stops `newgidmap` working inside the container.

Checked against the published image here:

```bash
podman run --rm --platform linux/amd64 docker.io/pkgforge/archlinux:latest bash -c \
  'pacman -Sy --noconfirm attr >/dev/null 2>&1; getfattr -d -m - /usr/bin/newgidmap'
```

```
/usr/bin/newgidmap: security.capability=0sAQAAAkAAAAAAAAAAAAAAAAAAAAA=
/usr/bin/newuidmap: security.capability=0sAQAAAoAAAAAAAAAAAAAAAAAAAAA=
```

⭐ **The capability xattrs survive here.** The reported defect does not
reproduce against this image.

⚠ **It is a warning for D6.** A rootfs tarball published as a release asset
loses those xattrs unless the tar carries `--xattrs`, which is the option at
`scripts/make-rootfs.sh:89`. Publishing the artefact without it would ship
exactly the defect this issue describes.

### Others noted and not opened

`#76` a mirror problem, `#72` a locale that cannot be generated after the strip,
`#67` and `#56` an alpm library that fails to initialise on older host kernels,
`#60` config files proposed for `NoExtract`. Titles only.

## What this study did not do

- No build was run. `make` needs `devtools`, `fakechroot` and an Arch host.
- No image was reproduced. `REPRO.md`'s procedure was read, not executed.
- `.gitlab-ci.yml`, `docker-library.template`, `Dockerfile.template`,
  `scripts/make-dockerfile.sh` and `sigstore-param-file.yaml` were listed but
  not read line by line.
- ⛔ No issue comment was read, for the 401 above. No merge request was fetched,
  so `MR !13`, named in issue 55 as the change that introduced the exclusions,
  was not opened.
- Only two of the 79 issues were read beyond their titles.
- Nothing was written to the upstream project. Reads only.
