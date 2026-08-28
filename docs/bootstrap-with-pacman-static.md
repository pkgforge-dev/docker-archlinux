# Bootstrapping an Arch root with `pacman-static`

Build a working Arch Linux root on a host that has no `pacman`, no `libalpm` and
no Arch keyring, using a statically linked `pacman` this repository builds from
source.

⛔ The binary is built here, never downloaded. `scripts/build-pacman-static`
fetches only what `bootstrap/pacman-static/sources.pin` names, checks every
tarball against its `sha256`, and checks out `pacman` at a pinned commit.

⭐ That commit is the one every image this repository publishes is built from.
The anchor tag family is `<alias>-7.1.0.r9.g54d9411-<pkgrel>`, and `g54d9411` is
that commit abbreviated, so the binary and the image's own `pacman` come from
one source. `tests/static/85-pacman-static-pin.sh` asserts it.

## What the host needs

No cross compiler and no `gcc`. `zig cc` is the compiler, the linker and the
archiver, and it carries the musl sources for every target.

| tool | why |
| --- | --- |
| `curl` | fetch the sources |
| `git` | check out `pacman` at its pinned commit |
| `tar`, `xz`, `bzip2`, `gzip` | unpack |
| `make`, `patch`, `cmp` | build |
| `cmake`, `meson`, `ninja` | build |
| `pkg-config` | dependency resolution |
| `perl` | OpenSSL's `Configure` |
| `python3` | meson |
| `gperf` | libseccomp |
| `readelf` | the static linkage check, and the lock object measurement |
| `qemu-user-static` | optional, to run a foreign binary |

On this repository's own image:

```bash
pacman -Sy --noconfirm --needed meson ninja cmake perl python git patch make \
  pkgconf binutils file diffutils gperf qemu-user-static
```

On Debian or Ubuntu:

```bash
apt-get install -y --no-install-recommends curl ca-certificates git tar \
  xz-utils bzip2 gzip zstd make patch cmake ninja-build pkg-config perl \
  python3 binutils file meson gperf qemu-user-static
```

## Build the binary

```bash
WORK=/tmp/pacman-static OUT=/tmp/dist scripts/build-pacman-static amd64
```

One of `amd64`, `arm64`, `armv7`, `loong64`, `riscv64`, `ppc`, `ppc64`,
`ppc64le`. `WORK` is reused between architectures, so the sources are fetched
once. It prints the size, the `sha256`, the ELF machine and, when the emulator
is installed, what the binary reported when it was run.

⚠ With no emulator for that target the run column reads `NOT MEASURED`, in the
output and in the evidence file. It is never a dash and never a pass.

The evidence file beside the binary records every source, its version, its URL
and its `sha256`, the `pacman` commit, and the three checks:

```bash
jq '{arch, triple, pacman_commit, reported_version, elf_machine, interp_segments, sha256}' \
  /tmp/dist/pacman-static-amd64.json
```

## Check it yourself

```bash
BIN=/tmp/dist/pacman-static-amd64

file "$BIN"
readelf -lW "$BIN" | awk '/INTERP/ { n++ } END { print n + 0 }'
"$BIN" --version
```

The `INTERP` count must be `0`. That is what static means: no dynamic loader is
named, so the binary runs on a system whose `libc` is missing or broken.

## Build a root with it

The two passes are not interchangeable. The first has no keyring to verify
against, because there is no `gpg` inside a static `pacman`: `pacman-key` is a
shell script that drives `gpg`. The second runs inside the new root, where
`gpg` now exists, and is the pass that makes the root trustworthy.

⛔ Nothing installed in pass one is verified. A bootstrap that stops there has
proved that the download worked and nothing about trust.

### Pass one, unverified

```bash
export ROOT=/tmp/archroot
export PACMAN=/tmp/dist/pacman-static-amd64

mkdir -p "$ROOT/var/lib/pacman" "$ROOT/var/cache/pacman/pkg" \
         "$ROOT/etc/pacman.d/hooks" "$ROOT/etc/pacman.d/gnupg" "$ROOT/var/log"
```

⚠ `--hookdir` must already exist. `pacman` creates `--dbpath` and `--cachedir`
and refuses a missing `--hookdir`.

⛔ Redirect all six paths, not just `--root`. `pacman` keeps its database,
cache, hooks, keyring and log at compiled-in absolute paths, and one that is not
redirected is written on the host.

Write a config outside the root, so nothing in the transaction can rewrite it.
This repository already ships one per architecture, and it is the config that
built the published image:

```bash
mkdir -p /tmp/pacboot
sed 's|^SigLevel .*|SigLevel = Never|' rootfs/amd64/etc/pacman.conf > /tmp/pacboot/pacman.conf
sed 's|^Include .*|Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch|' \
  -i /tmp/pacboot/pacman.conf
```

```bash
pac() {
  "$PACMAN" --config /tmp/pacboot/pacman.conf --root "$ROOT" \
    --dbpath "$ROOT/var/lib/pacman" --cachedir "$ROOT/var/cache/pacman/pkg" \
    --hookdir "$ROOT/etc/pacman.d/hooks" --gpgdir "$ROOT/etc/pacman.d/gnupg" \
    --logfile "$ROOT/var/log/pacman.log" "$@"
}

pac -Sy --noconfirm
pac -S --noconfirm base
```

⚠ `base` is the target, not a hand picked minimal set. Install scriptlets run
with the target root's own shell, so a root without `bash` cannot run them.

Count what landed rather than trusting the exit status:

```bash
ls -1 "$ROOT/var/lib/pacman/local" | awk '!/ALPM_DB_VERSION/ { n++ } END { print n + 0 }'
```

### Pass two, verified

⛔ Do not bind mount the host's `/dev`. If the later `umount` fails, an `rm -rf`
on the root deletes the host's device nodes. Five `mknod` calls are enough.

```bash
mknod -m 666 "$ROOT/dev/null"    c 1 3
mknod -m 666 "$ROOT/dev/zero"    c 1 5
mknod -m 666 "$ROOT/dev/random"  c 1 8
mknod -m 666 "$ROOT/dev/urandom" c 1 9
mknod -m 666 "$ROOT/dev/tty"     c 5 0
cp -f /etc/resolv.conf "$ROOT/etc/resolv.conf"
```

The keyring to populate is not `archlinux` on every port:

| architecture | keyring package | `--populate` argument |
| --- | --- | --- |
| `amd64`, `riscv64` | `archlinux-keyring` | `archlinux` |
| `arm64`, `armv7` | `archlinuxarm-keyring` | `archlinuxarm` |
| `loong64` | `archlinux-lcpu-keyring` | `archlinux-lcpu` |
| `ppc`, `ppc64`, `ppc64le` | `archpower-keyring` | `archpower` |

Each is pinned by `sha256` and by its trusted fingerprints in
`bootstrap/keyrings/*.pin`, so the keyring can be verified before it is trusted
rather than after.

```bash
chroot "$ROOT" /usr/bin/bash -c 'pacman-key --init && pacman-key --populate archlinux'
cp rootfs/amd64/etc/pacman.conf "$ROOT/etc/pacman.conf"
cp rootfs/amd64/etc/pacman.d/mirrorlist "$ROOT/etc/pacman.d/mirrorlist"
chroot "$ROOT" /usr/bin/bash -c 'pacman -Sy --noconfirm'
```

The shipped config carries `SigLevel = Required DatabaseOptional`, so a second
sync that succeeds is the proof that verification works.

### Prove the root runs

```bash
chroot "$ROOT" /usr/bin/bash -c 'echo it-runs'
chroot "$ROOT" /usr/bin/pacman --version
```

⭐ This is the check that means "a working root". It executes the new root's own
dynamically linked binaries with the new root's own loader. Nothing about the
static builder is involved any more, including its libc and its architecture.

## Turn it into an image and test it

```bash
tar --numeric-owner -C "$ROOT" -c . | podman import - localhost/archlinux:bootstrapped
```

```bash
SOURCE_COMMIT="$(git rev-parse HEAD)" BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  scripts/gen-evidence amd64 localhost/archlinux:bootstrapped linux/amd64 /tmp/ev.json
IMAGE=localhost/archlinux:bootstrapped PLATFORM=linux/amd64 EVIDENCE=/tmp/ev.json \
  tests/run.sh image
```

## Repair a system whose libc is gone

The job the binary exists for. From rescue media, with the broken root mounted
at `/mnt`:

```bash
./pacman-static-amd64 -r /mnt -S --noconfirm glibc
./pacman-static-amd64 -r /mnt -Qkk
```

⚠ Under `-r` the compiled-in `--gpgdir` and `--hookdir` resolve inside `/mnt`,
so this case needs no path redirection. It is the empty-directory case above
where missing one writes on the host.

⚠ The architecture must match. A `ppc64le` root cannot be repaired with the
`amd64` binary.

## What this does not remove

| still required | why |
| --- | --- |
| a kernel that can execute the binary | it is static, not a bootloader |
| `/dev/urandom` | OpenSSL and gpg need entropy, and fail in ways that look like a `pacman` bug |
| `/etc/ssl/certs/ca-certificates.crt` | `curl` was built with that path, not with embedded certificates. Use an `http` mirror if the host has no bundle |
| a reachable mirror | the binary removes the container image from the trust root, not the network |

## What the binary is not

⚠ `libcurl` here is built without brotli and without nghttp2, so it negotiates
HTTP/1.1 and does not accept a `br` content encoding. Neither is needed to fetch
a package. The evidence file records the whole source set, so the difference is
a measurement rather than a claim.

⚠ Every non `x86_64` claim in this repository is a `qemu-user` claim. `qemu-user`
emulates the instruction set and passes syscalls to the host kernel: it does not
exercise the target's kernel or its page size.

## Licensing

The binary is `pacman`, which is `GPL-2.0-or-later` however it was built. A
release asset carries the pinned source tarball beside it, which is the source
offer. `bootstrap/pacman-static/sources.pin` names every input by URL and
`sha256`, so the exact sources are recoverable from the pin alone.
