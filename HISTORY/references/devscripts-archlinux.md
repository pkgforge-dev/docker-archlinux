# pkgforge/devscripts archlinux.sh

⚠ **Scratch paths in this document** name fixtures under `.tmp/`, which is
gitignored and wiped between sessions. They record what a measurement was
taken against, not something a reader can open. ⛔ Nothing in the
repository depends on them. To re-run one, copy the tree to a scratch
directory, rebuild the fixture the surrounding text describes, and point the
command at that copy.

Reference study of the direct consumer. `pkgforge/archlinux-base` is built by
this script, and the script's first line of work runs inside an image this
repository publishes.

## Provenance

| item | value |
| --- | --- |
| repository | `https://github.com/pkgforge/devscripts` |
| path | `Github/Runners/bootstrap/archlinux.sh` |
| repository HEAD when read | `05574a0f8fa966a7d0e37032a4736e5066d36b8e`, 2026-08-22 |
| last commit to touch the file | `dd325b09cc0def9a267bf77cd6a11395cfc15e37`, 2025-01-30 |
| file fetched at | the HEAD above, 138 lines |
| sha256 of the file read | `e84135f0dbc005f4da86d5c4e21675eae7b5cfd0abe308811f2ace616366fdfd` |
| studied on | 2026-08-26 |

```bash
gh api 'repos/pkgforge/devscripts/commits?path=Github/Runners/bootstrap/archlinux.sh&per_page=3' \
  --jq '.[] | "\(.sha)\t\(.commit.author.date)"'
curl -sSL "https://raw.githubusercontent.com/pkgforge/devscripts/05574a0f8fa966a7d0e37032a4736e5066d36b8e/Github/Runners/bootstrap/archlinux.sh" -o devscripts-archlinux.sh
sha256sum devscripts-archlinux.sh
```

## Verdict: adopt

⭐ **What transfers is not code. It is the contract this script depends on.**
The script reads an image and patches it with `sed`. Every patch it makes is a
statement about what the image contains. Those statements are now assertions in
`tests/image/50-consumer-contract.sh`, so a change here that would break the
consumer fails a test instead of a downstream build.

## The contract, and what each line of the script needs

| script line | what it does | what the image must provide |
| --- | --- | --- |
| 15 | `docker run --name archlinux-base --privileged "pkgforge/archlinux:latest" bash -l -c` | the Docker Hub `:latest` tag, resolving for the runner's own architecture, with a working `bash` login shell |
| 17 | `pacman -y --sync --refresh --sysupgrade --noconfirm --debug` | ⭐ a populated keyring. This runs **before** line 24 sets `SigLevel = Never`, so the first upgrade verifies signatures. |
| 22 | `sed '/DownloadUser/d' -i /etc/pacman.conf` | nothing. The line is absent here, so the delete is a no-op. |
| 24 | `sed '0,/^.*SigLevel\s*=.*/s//SigLevel = Never/'` | ⛔ the **first** `SigLevel` line in `/etc/pacman.conf` must be the global one under `[options]`. The patch is positional. |
| 26 | `sed '/#\[multilib\]/,/#Include = .*/s/^#//'` | a commented `#[multilib]` block. ⚠ **Absent here. See below.** |
| 35 | `echo "disable-scdaemon" \| tee /etc/pacman.d/gnupg/gpg-agent.conf` | `/etc/pacman.d/gnupg/` must exist and be writable |
| 39 to 45 | writes `/etc/locale.conf`, appends `/etc/locale.gen`, runs `locale-gen` | `locale-gen`, plus the `usr/share/i18n` data that survives `NoExtract` |
| 105 | `docker export ... --output rootfs.tar` | nothing from the image. Recorded because D6 proposes publishing that same artefact. |

Measured against the published image on 2026-08-26:

```bash
podman run -i --rm --platform linux/amd64 docker.io/pkgforge/archlinux:latest bash -s < .tmp/phased/consumer-probe.sh
```

| item | result |
| --- | --- |
| `bash -l -c` | prints `login-shell-ok` |
| first `SigLevel` line | line 42, `SigLevel    = Required DatabaseOptional`, the global one |
| `/etc/pacman.d/gnupg` | present, carrying `pubring.gpg`, `trustdb.gpg`, `gpg.conf` |
| keys in the keyring | 182 |
| `locale-gen` | `/usr/sbin/locale-gen` |
| `usr/share/i18n/charmaps` | `ANSI_X3.4-1968.gz`, `UTF-8.gz` |
| `locale -a` | `C`, `C.utf8`, `en_US.utf8`, `POSIX` |
| `IMAGE_VERSION` | `2026.08.26` |

And the load-bearing operation, line 17, run end to end:

```bash
podman run --rm --platform linux/amd64 docker.io/pkgforge/archlinux:latest \
  bash -l -c 'pacman -y --sync --refresh --sysupgrade --noconfirm 2>&1 | tail -25; echo "PACMAN_RC=${PIPESTATUS[0]}"'
```

```
:: Synchronizing package databases...
 core downloading...
 extra downloading...
:: Starting full system upgrade...
 there is nothing to do
PACMAN_RC=0
```

⭐ **This is the measurement that matters most.** A signature-verifying full
upgrade succeeds against the shipped keyring. If `pacman-key --populate` were
ever dropped from the build, this consumer would fail on its first command.

## Finding 1: the multilib patch has never matched

Line 26 of the script uncomments a `#[multilib]` block. No `pacman.conf` in this
repository has ever contained one:

```bash
git log --oneline -S 'multilib' --all -- .
```

No output. The string has never appeared in the tree, at any commit.

⛔ **Nothing is changed in response.** Adding the block would make the
consumer's `sed` fire and enable a repository in their image that has never been
enabled there. Policy 7 requires an existing consumer to notice no difference,
and silently switching multilib on is a difference.

⚠ The state is now pinned by a test, so adding the block later is a deliberate
change with a failing test in front of it rather than a silent one.

## Finding 2: the SigLevel patch is positional and currently safe

`0,/^.*SigLevel\s*=.*/s//SigLevel = Never/` replaces the first matching line.
In `rootfs/*/etc/pacman.conf` the order is:

```bash
grep -n 'SigLevel' rootfs/amd64/etc/pacman.conf
```

```
42:SigLevel    = Required DatabaseOptional
43:LocalFileSigLevel = Optional
44:#RemoteFileSigLevel = Required
106:#SigLevel = Optional TrustAll
```

Line 42 is the global setting, so the patch lands where the script intends.

⚠ **Moving `LocalFileSigLevel` above it would silently redirect the patch**, and
the consumer would keep signature checking on where they expect it off. The
ordering is asserted by the test.

## Finding 3: the consumer strips what this image already omits

Lines 71 to 94 delete `usr/share/man`, `usr/share/doc`, `usr/share/info`,
`usr/share/gtk-doc`, `usr/share/help` and all locales except `en` and `en_US`.
Decisions 5, 6 and 7 already remove those through `NoExtract`, so the deletes
find little. ⭐ **This is independent evidence that the decisions match what the
direct consumer wants**, reached without asking.

⚠ The two mechanisms are not equivalent and the difference is the point.
`NoExtract` is a config line a consumer comments out to get the files back on
reinstall. A `rm -rf` is not reversible in the layer that ran it.

## What this study did not do

- `archlinux_hooks.sh`, fetched by line 36 of the script, was not read.
- The `fake-sudo-pkexec.tar.zst` and `yay` release assets, fetched at lines 63
  and 68, were not fetched or inspected.
- No other script under `Github/Runners/bootstrap/` was read.
- The consumer's own tracker was not read. `pkgforge/devscripts` covers many
  distributions and its issues were not filtered for this file.
- Nothing was written to the upstream repository. Reads only.
