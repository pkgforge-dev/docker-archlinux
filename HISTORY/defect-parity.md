# Defect parity against the upstream tracker

`archlinux/archlinux-docker` records what went wrong for somebody running an
Arch container. Each report is a question about **this** image: is the same
thing true here, and does anything stop it coming back. Measured 2026-08-27
against `docker.io/pkgforge/archlinux:latest`, on all four architectures unless
a row says otherwise.

⛔ **Reads only.** Policy 1. Nothing was filed, commented or proposed upstream.

## How the tracker was read

```bash
B="https://gitlab.archlinux.org/api/v4/projects/archlinux%2Farchlinux-docker"
curl -sS "$B/issues?state=all&per_page=100" | jq -r '.[] | "\(.iid)\t[\(.state)]\t\(.title)"'
```

79 issues, 15 open and 64 closed. ⭐ **Closed is where the decisions are**, so
the closed set was read too. Eleven closed issues were followed into their
descriptions because each names a failure mode an image can carry: 18, 23, 24,
52, 58, 59, 64, 70, 98, 103 and 107.

⛔ **Comments need authentication and this account has none.** Re-checked on
2026-08-27, both `$B/issues/55/notes` and `$B/issues/106/notes` answer
`401 Unauthorized`. Every issue here is read by title and description only, so
where a maintainer explained a decision in a comment, that explanation is not
part of this.

## Verdicts

| issue | state | the failure mode | this image |
| --- | --- | --- | --- |
| 55 | open | files withheld that the package database still lists | fixed, guarded by `tests/static/80-docs-claims.sh` |
| 106 | open | extended attributes lost while packing | **not present**, now guarded |
| 70 | closed | a setuid bit lost between package and image | **not present**, now guarded |
| 72, 59, 24 | open, closed, closed | a locale that cannot be generated | **not present**, now guarded |
| 60 | open | `/etc/hosts` and `/etc/resolv.conf` block an upgrade | **does not apply**, and its proposed fix is forbidden here |
| 67, 56 | open | `failed to initialize alpm library` | **not present**, now guarded |
| 103 | closed | the pacman sandbox on a kernel without landlock | **not reproducible** on pacman 7.1.0 |
| 66 | open | a tag outliving the artefact it names | **not present**, 322 tags checked |
| 80, 64 | open, closed | a package binary not on `PATH` | was present, inherited from Arch packaging. **Fixed here**, with `PATH` untouched |
| 107 | closed | a profile script that errors on every login shell | **not present**, guarded by systemd itself |
| 18 | closed | `pacman-key` cannot locally sign a third party key | **present, deliberately.** No private key is shipped, and that is the safer half of the trade |
| 23 | closed | `pacman-key` calling a tool the image lacks | **not present**, now guarded |
| 52 | closed | users and groups the packages expect are missing | **not present**, 18 accounts and 50 groups |
| 98 | closed | pacman hooks not firing in an unprivileged container | **not applicable**, the hooks in that report belong to packages a consumer installs |
| 110 | open | systemd in a rootless container | out of scope as a feature, and the measurement it needed found a defect here that is **now fixed** |

19 issues in 14 classes. 33 of the 35 assertions in
`tests/image/60-defect-parity.sh` come from this table. The other two are the
meta-assertion that the probe ran at all, and a count of the scripts under
`/etc/profile.d` that keeps assertion 17 from passing on an empty directory.
Every one has been seen to fail, in
[`tests-seen-to-fail.md`](tests-seen-to-fail.md).

⭐ **Three defects were found in this image and all three are fixed**: the
shipped `/etc/machine-id`, the two missing `DisableSandbox` comments, and issue
80. A local build of the fixed tree passes 35 of 35 on `linux/amd64` and
`linux/arm64`.

---

## 106, extended attributes are not preserved on unpacking

The report: `newgidmap` cannot be used inside a container because it needs
`security.capability`, and the attribute does not survive the rootfs being
packed and unpacked. ⚠ The file is still there and still executable, so nothing
looks wrong until a rootless container inside this one fails to map a uid.

```bash
podman run --rm --platform linux/amd64 <image> \
  getfattr -d -m - --absolute-names /usr/bin/newgidmap /usr/bin/newuidmap
```

| image | `/usr/bin/newuidmap` | `/usr/bin/newgidmap` |
| --- | --- | --- |
| `docker.io/pkgforge/archlinux:latest` | `0100000280000000000000000000000000000000` | `0100000240000000000000000000000000000000` |
| `docker.io/library/archlinux:latest` | none | none |

Identical on `amd64`, `arm64`, `armv7` and `riscv64`. The two values are v2
capability sets carrying `CAP_SETUID` and `CAP_SETGID`.

⭐ **This image does not have the defect and the official image does.** Guarded
by assertions 3 and 4.

## 70, a setuid bit dropped between the package and the image

The same class, one step more visible. `passwd` without its setuid bit fails
only when a user who is not root runs it.

```bash
podman run --rm --platform linux/amd64 <image> \
  find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -printf '%M %u %g %p\n'
```

| fact | value |
| --- | --- |
| `/usr/bin/passwd` | `-rwsr-xr-x`, on all four architectures |
| files keeping a setuid or setgid bit | 14, on all four architectures |
| the same in `docker.io/library/archlinux:latest` | `-rwsr-xr-x` |

The 14: `chage`, `chfn`, `chsh`, `gpasswd`, `ksu`, `mount`, `newgrp`, `passwd`,
`su`, `umount`, `unix_chkpwd`, `wall`, `write`, `dbus-daemon-launch-helper`.

Guarded by assertions 5 and 6. ⚠ The count is asserted as a floor of 10, not as
14, because a package update may legitimately move it.

## 72, 59 and 24, a locale that cannot be generated

Three reports over three years, all the same thing: the locale definitions were
withheld, so `locale-gen` could build nothing the image did not already have.

```bash
podman run --rm --platform linux/amd64 <image> bash -c '
  echo "ja_JP.UTF-8 UTF-8" >> /etc/locale.gen
  locale-gen
  locale -a
  LC_ALL=ja_JP.UTF-8 locale charmap'
```

| fact | this image | `docker.io/library/archlinux:latest` |
| --- | --- | --- |
| `/usr/share/i18n/charmaps` entries | 233 | 2 |
| `/usr/share/i18n/locales` entries | 371 on `amd64` and `riscv64`, 370 on `arm64` and `armv7` | not counted, `ja_JP` absent |
| `/usr/share/i18n/locales/ja_JP` | present | missing |
| `ja_JP.UTF-8` after `locale-gen` | generated, listed as `ja_JP.utf8` | cannot be generated |
| `LC_ALL=ja_JP.UTF-8 locale charmap` | `UTF-8` | not reached |
| `LC_ALL=ja_JP.UTF-8 date +%A` | differs from the `LC_ALL=C` output | not reached |

`zh_CN`, `ru_RU` and `ko_KR` sources are present too.

⭐ **No preparation is needed.** Appending one line and running `locale-gen` is
enough, which is what issue 72 asks for. This follows from decision 5: nothing
is withheld, so nothing has to be restored first.

⛔ **`locale-gen` reports success while failing**, which is why the exit status
is not the assertion. Issue 59 records the exact output:

```
  ja_JP.UTF-8... done [error] cannot open locale definition file `ja_JP': No such file or directory
```

It prints `done`, prints the error beside it, and exits 0. Confirmed here rather
than taken on trust: against the fixture with `/usr/share/i18n/locales` emptied,
assertion 25 still passes and assertions 26, 27 and 28 are the ones that fail.
So the exit status is not the assertion. Three checks follow the run instead:
the locale is listed, it reports charmap `UTF-8`, and it changes what `date`
prints. A locale can be listed and still carry none of the data that makes it
useful.

Guarded by assertions 19 to 28. ⚠ The counts are asserted as floors of 100 and
300, because the exact numbers differ by architecture.

## 60, `/etc/hosts` and `/etc/resolv.conf`

The report: the container runtime bind mounts its own versions over both, so an
upgrade of the `filesystem` package cannot write them, and the proposed fix is
`NoExtract`.

⛔ **That fix is the one this repository reverted.** See
[`noextract-reverted.md`](noextract-reverted.md). So the question is whether the
defect exists here without it.

```bash
podman run --rm --platform linux/amd64 <image> bash -c '
  grep -E " /etc/" /proc/mounts
  pacman -Sy --noconfirm >/dev/null
  head -2 /etc/hosts
  pacman -S --noconfirm filesystem
  head -2 /etc/hosts
  ls /etc/*.pacnew'
```

| fact | value |
| --- | --- |
| bind mounted by podman over `/etc` | `/etc/hostname`, `/etc/resolv.conf`, `/etc/hosts`, all `rw` |
| `pacman -S filesystem` | exit 0 |
| `/etc/hosts` after the reinstall | unchanged, still the runtime's version |
| `/etc/resolv.conf` after the reinstall | unchanged, still the runtime's version |
| `.pacnew` written for either | none |
| entries in the `filesystem` package's `%BACKUP%` section | 17, including `etc/hosts` and `etc/resolv.conf` |

⭐ **The backup handling is what saves it.** pacman leaves a `%BACKUP%` file
alone when the on-disk copy differs from the package's, so the runtime's version
survives without anything being withheld. That is a property of the package, so
assertions 14 and 15 assert that the package still declares both paths. If a
future `filesystem` drops them from `%BACKUP%`, the defect arrives here and the
test says so.

⚠ Measured under podman, which bind mounts both read-write. A runtime that
mounts them read-only, or a container run with `--read-only`, is not covered.

## 67 and 56, `failed to initialize alpm library`

Both reports end in `could not find or read directory: /var/lib/pacman/`.

| fact | value |
| --- | --- |
| `/var/lib/pacman` | a directory, all four architectures |
| `/var/lib/pacman/local` | a directory, 138 entries on `amd64`, `arm64` and `armv7`, 136 on `riscv64` |
| `/var/lib/pacman/sync` | a directory, 0 entries, rebuilt by the consumer's first `pacman -Sy` |
| `pacman -Qq` | lists 137 packages on `amd64` |

Guarded by assertions 11, 12 and 13. ⚠ Issue 56 also blames host syscalls the
runtime blocks. That is the same ground as issue 103 below.

## 103, the pacman sandbox without landlock

Closed upstream. The report: `restricting filesystem access failed because the
landlock ruleset could not be applied`. Upstream's remedy is visible in their
shipped config, which carries `DisableSandboxFilesystem` uncommented.

A seccomp profile was written to take landlock away, and pacman was run under it
twice, once with the syscalls answering `ENOSYS` and once `EPERM`:

```bash
cat > no-landlock.json <<'EOF'
{ "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [ { "names": ["landlock_create_ruleset", "landlock_add_rule",
                            "landlock_restrict_self"],
                  "action": "SCMP_ACT_ERRNO", "errnoRet": 38 } ] }
EOF
podman run --rm --platform linux/amd64 --security-opt seccomp=no-landlock.json \
  <image> pacman -Sy --noconfirm --needed which
```

| landlock answers | result |
| --- | --- |
| `ENOSYS` | `pacman -Sy` exits 0, no warning printed |
| `EPERM` | `pacman -S which` installs and exits 0, no warning printed |

⭐ **The defect is not reproducible on pacman 7.1.0, libalpm 16.0.1.** A sandbox
that cannot be applied no longer stops the transaction, so this image needs no
config change to survive a kernel without landlock. ⚠ It is not asserted by a
test: the check needs a seccomp profile and a package install over the network,
which does not belong in the image suite. Re-run it by hand from the commands
above when pacman's major version changes.

⚠ This measurement surfaced a separate finding about the shipped `pacman.conf`,
below.

## 66, a tag outliving the artefact it names

The report is about upstream deleting rootfs artefacts while leaving the tags
that name them. ⛔ Nothing is ever removed from either registry here, so the
question is whether a registry's own housekeeping can produce the same shape.

Every tag on both registries was resolved:

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:pkgforge-dev/archlinux:pull&service=ghcr.io" | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://ghcr.io/v2/pkgforge-dev/archlinux/tags/list?n=1000" | jq -r '.tags[]'
```

| registry | tags | resolving to a manifest |
| --- | --- | --- |
| `ghcr.io/pkgforge-dev/archlinux` | 161 | 161, all HTTP 200 |
| `docker.io/pkgforge/archlinux` | 161 | 161, all HTTP 200 |

Then the blobs behind a sample, config and every layer, by `HEAD` on
`/v2/<repo>/blobs/<digest>`:

| tag | linux manifests | blobs | missing |
| --- | --- | --- | --- |
| `v2024.12.25`, the oldest | 6 | 24 | 0 |
| `v2025.01.16` | 6 | 24 | 0 |
| `v2026.05.15` | 4 | 16 | 0 |
| `v2026.08.26` | 4 | 16 | 0 |
| `latest` | 4 | 16 | 0 |
| `amd64-7.1.0.r9.g54d9411-2` | 1 | 4 | 0 |
| `riscv64` | 1 | 4 | 0 |

⚠ The two oldest tags carry six linux manifests because they predate the removal
of `ppc64le` and `386`. See [`removed-architectures.md`](removed-architectures.md).

⚠ **Blobs were sampled, not swept.** 7 tags of 161. A full sweep is roughly
2600 requests against each registry, which is a job rather than a measurement.
Tag resolution was swept in full on both.

⚠ **Two traps cost time here and are worth knowing.** Native `jq` on Windows
writes CRLF, so a tag read from it arrives as `latest\r` and curl answers
`URL rejected: Malformed input to a URL function`. And native curl does not
reliably write to `/dev/null`, which is an MSYS path, so `-o /dev/null` returns
`000` for every request and reads as though every tag were gone. ⛔ A sweep that
reports the same code for all 161 has failed, not measured.

## 80 and 64, a package binary not on `PATH`

⭐ **This one is present here.** It is inherited from Arch packaging rather than
introduced by the image, and the official image has it identically.

```bash
podman run --rm --platform linux/amd64 <image> bash -c '
  pacman -Sy --noconfirm --needed perl-image-exiftool
  pacman -Qlq perl-image-exiftool | grep bin/
  command -v exiftool || echo NOT-ON-PATH
  bash -lc "command -v exiftool"'
```

| fact | value |
| --- | --- |
| where the binary lands | `/usr/bin/vendor_perl/exiftool` |
| default `PATH` | `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` |
| `command -v exiftool` | not found |
| `bash -lc 'command -v exiftool'` | `/usr/bin/vendor_perl/exiftool` |
| what adds it | `/etc/profile.d/perlbin.sh`, shipped by `perl`, read only by a login shell |
| `Config.Env` `PATH` in `docker.io/library/archlinux:latest` | byte for byte the same string |

So `podman run <image> exiftool` failed and `podman run <image> bash -lc exiftool`
worked.

⭐ **Fixed here on 2026-08-27, without touching `PATH`.** Setting `ENV PATH`
was refused: this image's `PATH` is byte for byte the official image's,
consumer tooling reads it, and changing it would make this image disagree with
a normal Arch install. So the executables come to `PATH` instead of `PATH`
going to them.

`/etc/pacman.d/hooks/bindir-links.hook` runs
`/usr/local/lib/docker-archlinux/bindir-links` after any transaction touching
`/usr/bin`. It symlinks each executable in the three perl bindirs into
`/usr/local/bin`, which is on `PATH`, is owned by `filesystem`, and holds
nothing any package ships.

Measured on a local build of the changed tree:

| step | result |
| --- | --- |
| before installing anything | `command -v exiftool` finds nothing |
| `pacman -S perl-image-exiftool` | the hook reports `30 linked, 0 pruned in /usr/local/bin` |
| after | `command -v exiftool` is `/usr/local/bin/exiftool` |
| `podman run <image> sh -c '...; exec exiftool -ver'` | `13.55` |
| `PATH` | unchanged, the same string as before |
| links that shadow a `/usr/bin` entry | 0 of 30 |
| links pointing anywhere but a perl bindir | 0 of 30 |
| `pacman -Qlq` listed against the filesystem | 39106 listed, 1 missing, still only `/var/lock` |

⛔ **Three rules make this safe under policy 7**, and each is an assertion in
section 9 of `tests/image/60-defect-parity.sh`:

- a name that already resolves under `/usr/bin` is never linked, so nothing a
  consumer could run before resolves anywhere new;
- a link goes as soon as its target does, so no dangling entry is left on
  `PATH`;
- a link goes when a package later claims the name, so the package wins.

⚠ **The hook also runs during the bootstrap**, because `pacman -r` reads hooks
from the target root and `rootfs/any` is in place before `pacstrap-docker`
runs. That is not new: `package-cleanup.hook` has always run there, and it is
how `/var/cache/pacman/pkg` ends up empty in the image. Verified by a
`--no-cache` `linux/arm64` build, where the hook runs a foreign architecture
`/bin/sh` under emulation: the build succeeds, the cache is empty, and the
image passes 35 of 35.

Issue 64 is the other half: `/usr/sbin`, `/sbin` and `/bin` are on `PATH` and
are symlinks, and a tool that does not resolve symlinks derives wrong paths from
them. They are still on `PATH` here, which is what every consumer has seen. What
is asserted instead is the property those tools depend on:

| link | target |
| --- | --- |
| `/usr/sbin` | `bin` |
| `/sbin` | `usr/bin` |
| `/bin` | `usr/bin` |
| `/lib` | `usr/lib` |
| `/usr/lib64` | `lib` |

Guarded by assertions 7, 8, 9 and 10.

## 107, a profile script that errors on every login shell

Closed upstream on 2025-12-19. The report: `/etc/profile.d/80-systemd-osc-context.sh`
reads `/etc/machine-id` unconditionally, so a shell prints an error before every
command when the file is missing.

⭐ **systemd fixed it in the package**, and this image carries the fixed version.
In `systemd 261.2-1` the read sits behind a test:

```sh
__systemd_osc_context_common() {
    if [ -f /etc/machine-id ]; then
        printf ";machineid=%.36s" "$(</etc/machine-id)"
    fi
```

Measured: with `/etc/machine-id` deleted, `bash -lc true` still writes 0 bytes to
stderr.

⚠ **So an assertion naming that one script would assert nothing.** Assertion 17
asserts the class instead, that no script under `/etc/profile.d` writes to
stderr, and assertion 16 counts the scripts so the quiet check cannot pass on an
empty directory. Both were seen to fail against fixtures.

## 18 and 23, pacman-key

Both closed. Issue 23: `pacman-key` is a shell script, and on an image without
`gawk` it fails with `/usr/sbin/pacman-key: line 214: awk: command not found`.
Issue 18: `pacman-key --lsign-key` cannot sign a third party key, because the
image carries no local signing key.

```bash
podman run --rm --platform linux/amd64 <image> \
  sh -c 'ls -la /etc/pacman.d/gnupg/; command -v awk gpg gpgconf sed grep'
```

| fact | value |
| --- | --- |
| `awk`, `gpg`, `gpgconf`, `sed`, `grep` | all on `PATH` |
| `/etc/pacman.d/gnupg/pubring.gpg` | 1371167 bytes |
| `/etc/pacman.d/gnupg/private-keys-v1.d` | absent |
| `/etc/pacman.d/gnupg/secring.gpg` | 0 bytes |

⭐ **Issue 23 is not present.** ⛔ **Issue 18 is present, deliberately, and it is
the right way round.** The build runs `pacman-key --init` and then removes
`private-keys-v1.d`, so the image carries a populated public keyring and no
private key. Shipping one would put the same secret in every consumer's image.
A consumer that needs to sign a third party key runs `pacman-key --init` first.

⚠ **Nothing tested that until now.** Removing the `rm -rf` line from the
`Dockerfile` would have shipped a private key with no assertion noticing.
Assertions 29 and 30 close both halves.

## 52, missing users and groups

Closed. The report is that a `systemd-sysusers` call moved out of the Dockerfile
and the accounts packages expect stopped being created.

| fact | value |
| --- | --- |
| `/etc/passwd` entries | 18 |
| `/etc/group` entries | 50 |
| `root`, `bin`, `daemon`, `mail`, `ftp`, `http`, `nobody`, `dbus`, `alpm` | all present |

Not present here: the sysusers hook runs during the bootstrap, and `dbus` (81)
and `alpm` (970) are both there, which are the two created by scriptlet rather
than shipped in the `filesystem` package. ⚠ Not asserted by a test. The accounts
come from packages, so a regression would be upstream's rather than this
repository's, and no consumer requirement names them.

## 98, pacman hooks in an unprivileged container

Closed. The report is that hooks needing `chroot` do not fire under a CI runner,
so the reporter runs the scripts by hand afterwards.

| fact | value |
| --- | --- |
| hooks this repository ships | 1, `/etc/pacman.d/hooks/package-cleanup.hook` |
| hooks packages ship | 16 under `/usr/share/libalpm/hooks/` |

⚠ **Not applicable as a defect of this image.** The failing hooks in that report
belong to packages a consumer installs, not to this image, and this image's own
hook is not one of them. Recorded so the next reader does not re-derive it.

## 110, systemd in a rootless container

The report: `dbus-broker` hangs because `/etc/machine-id` contains
`uninitialized`, and an empty file fixes it.

Out of scope as a feature: nothing here runs systemd, and no consumer has asked
for it. ⛔ **Recorded rather than pursued**, which is the outcome the brief asks
for. But the measurement it required found something else.

---

# Two findings, both decided

Both change what a consumer sees, which policy 7 makes the maintainer's call.
Both were put to the maintainer with the measurements below, and both were
decided on 2026-08-27. What follows is the measurement first, then the ruling.

## 1. `/etc/machine-id` is generated at build time and shipped

```bash
podman create --platform linux/amd64 <image> true    # then podman cp CID:/etc/machine-id
podman run --rm --platform linux/amd64 <image> pacman -Qo /etc/machine-id
```

| fact | value |
| --- | --- |
| `/etc/machine-id` in this image | present, 33 bytes, 32 hex characters and a newline |
| owned by a package | no. `error: No package owns /etc/machine-id` |
| value on `linux/amd64` of `:latest` | `23dd23bd2b634e6780fe5d378e9e6100` |
| value on `linux/arm64` of `:latest` | `b07399b9247148538ccfae8e15cf0480` |
| value on `linux/riscv64` of `:latest` | `59d7194c02e6406b8ec2e5570fbc971c` |
| `/etc/machine-id` in `docker.io/library/archlinux:latest` | absent |
| what writes it | `systemd 261.2-1`, whose `post_install` scriptlet calls `systemd-machine-id-setup` |

⛔ **Every container started from one published tag and architecture carries the
same machine ID**, on every host, for every consumer. `machine-id(5)` calls the
value confidential and says an image should ship the file **empty**, so that it
is provisioned when the container starts. `sd_id128_get_machine_app_specific()`
derives application identifiers from it, so a shared value is a shared seed.

⭐ **Ruled: truncate it to zero bytes.** That is what `machine-id(5)` asks of an
image, it is what issue 110 reports as the fix, and it keeps the file present so
nothing that reads it has to handle absence. ⛔ **Removing the file was refused**:
the official image ships none, but a missing file is upstream issue 107, and
issue 110 reports `dbus-broker` refusing to start without one.

Applied in the `Dockerfile`, final stage, in a block of its own:

```dockerfile
RUN <<EOS
  set -eu
  : > /etc/machine-id
  [ ! -s /etc/machine-id ]
EOS
```

The `[ ! -s ]` is there so the step's success means something. Measured on a
local `linux/amd64` build of the changed tree: `/etc/machine-id` is 0 bytes, and
the image suite passes all 59 assertions across its 6 files.

Assertion 18 now asserts both halves, present and empty, and each half has been
seen to fail. ⭐ The published image is the fixture for the second: it predates
this change, so it fails assertion 18 and passes the other 27.

⚠ **What is unmeasured.** Whether any consumer reads `/etc/machine-id`. It is
not among the eight things `pkgforge/devscripts` patches, checked in
[`references/devscripts-archlinux.md`](references/devscripts-archlinux.md).

⚠ **The old values stay published.** 161 tags on each registry carry an image
with a real machine ID and cannot be recalled. The change takes effect from the
next build.

## 2. The shipped `pacman.conf` has drifted from the stock one

Found while measuring issue 103. The comparison is against the `pacman.conf` the
`pacman` package itself installs, taken from the `.pacnew` a reinstall leaves:

```bash
podman run --rm --platform linux/amd64 <image> bash -c '
  pacman -Sy --noconfirm --needed pacman
  sed -n "/^\[options\]/,/^\[/p" /etc/pacman.conf.pacnew'
```

| directive | stock | `rootfs/<arch>/etc/pacman.conf` | deliberate |
| --- | --- | --- | --- |
| `Architecture` | `auto` | the target architecture | yes, the cross-architecture bootstrap needs it |
| `CheckSpace` | on | commented out | yes, and the comment above it says why |
| `DownloadUser = alpm` | present | **absent** | not recorded anywhere |
| `#DisableSandboxFilesystem` | present as a comment | **absent** | not recorded anywhere |
| `#DisableSandboxSyscalls` | present as a comment | **absent** | not recorded anywhere |

The `alpm` user exists in the image, `uid=970(alpm) gid=970(alpm)`. Without
`DownloadUser`, pacman downloads as root where a stock Arch install drops to
that user first, which is a wider surface than the distribution's own default.

The two commented directives are what a consumer uncomments on a host that
blocks landlock. Their absence is the shape of upstream issue 58, where a
commented default was dropped and users could no longer find it.

⭐ **Ruled: restore the two comments, and leave `DownloadUser` unset.**

⛔ **The omission is deliberate, not an oversight, and that is now recorded in
the configs themselves.** Dropping downloads to an unprivileged user breaks
enough consumer CI that patching it back out is a common workaround:

```bash
sed 's/DownloadUser = alpm/#DownloadUser = alpm/'
```

An image that never sets it costs a consumer who wants it one added line,
instead of costing every consumer who does not one removed line. ⚠ This is a
deliberate departure from policy 5's default reading, taken because the measured
cost to consumers is higher than the surface it removes.

Applied to all four `rootfs/<arch>/etc/pacman.conf`: a comment block saying why
`DownloadUser` is absent, then `#DisableSandboxFilesystem` and
`#DisableSandboxSyscalls` as comments. Behaviour is unchanged, since a comment
does nothing until somebody uncomments it.

`tests/static/45-pacman-conf-shape.sh` holds both, and holds the four files to
one `[options]` block so the next edit cannot land on one architecture and miss
three. 21 assertions, each seen to fail.

---

## What was not checked

- ⛔ **Comments on any issue.** 401 without credentials, re-checked 2026-08-27.
  Where a decision was explained in a comment, it is not here.
- The 64 closed issues were read by title. Eleven were followed into their
  descriptions because they name a failure mode this image can have. The other
  53 were judged from the title alone.
- Issue 76, `problem with geo.mirror.pkgbuild.com mirror`, and issues 81, 100,
  104 and 109, which are upstream's own pipeline and packaging arrangements.
  None of them describes something an image can carry.
- Blob existence for 154 of the 161 tags on each registry.
- Issue 60 under a runtime that bind mounts `/etc/hosts` read-only.
- Issue 103 on pacman versions other than 7.1.0.
