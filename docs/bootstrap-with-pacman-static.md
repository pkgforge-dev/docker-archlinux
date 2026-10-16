# Bootstrap an Arch root with `pacman-static`

This guide builds an Arch Linux root on a host that has no `pacman`, no `libalpm` and no Arch keyring. It uses `pacman-static-<arch>`: a statically linked `pacman` for one port.

There are two ways to get the binary:

- Download it from a release of this repository, then check `SHA256SUMS` and its evidence file.
- Build it from source with `scripts/build-pacman-static`.

Each command below runs from the root of a clone of this repository. Set `ARCH` to a port name first. `scripts/ports list` gives the port names.

```bash
export ARCH="${ARCH:?set ARCH to a port name from scripts/ports list}"
```

⭐ The binary and the images use the same `pacman` source. `bootstrap/pacman-static/sources.pin` pins the commit and its `describe` value. The anchor tags of the images end in the same `describe` value. `tests/static/85-pacman-static-pin.sh` checks that the commit and `describe` agree. The freshness workflow compares `describe` with the live anchor and raises the issue `pacman-static-pin` when they differ.

## Get the binary from a release

```bash
base="https://github.com/pkgforge-dev/docker-archlinux/releases/latest/download"
for f in "pacman-static-$ARCH" "pacman-static-$ARCH.json" SHA256SUMS; do
  curl -sSfLO --connect-timeout 15 --max-time 600 "$base/$f"
done
awk -v f="pacman-static-$ARCH" '$2 == f || $2 == f ".json"' SHA256SUMS | sha256sum -c
scripts/build-pacman-static --check-evidence "pacman-static-$ARCH.json"
chmod +x "pacman-static-$ARCH"
export PACMAN="$PWD/pacman-static-$ARCH"
```

`--check-evidence` needs `jq`. It checks three facts in the evidence file:

- A signer of the pin signed the `pacman` tag, and the build checked that signature.
- The binary ran under the emulator of its port and printed its version.
- The binary names no dynamic loader.

## Build the binary from source

### Host tools

The build needs no `gcc` and no cross compiler. `zig cc` is the compiler, the linker and the archiver, and it has the musl source for every port. The build downloads the pinned `zig`.

| tool | used for |
| --- | --- |
| `curl` | download the pinned tarballs |
| `sha256sum` | check each tarball against the pin |
| `tar`, `xz`, `bzip2`, `gzip` | extract the tarballs |
| `git` | fetch `pacman` at the pinned commit, and its signed tag |
| `gpg` | check the signature of the tag |
| `make`, `perl` | build the libraries (`perl` runs the OpenSSL `Configure`) |
| `pkg-config` | find the static libraries |
| `gperf` | build libseccomp |
| `meson`, `ninja` | build `pacman` |
| `readelf` | measure `pthread_mutex_t`, and check the ELF machine and `PT_INTERP` |
| `qemu-<cpu>-static` | optional: run the binary once. Without it the run is `NOT MEASURED` |
| `jq` | optional: read the evidence file, and `--check-evidence` |

The variable `HOST_TOOLS` in `scripts/build-pacman-static` holds the same list. The script checks each tool before it downloads anything.

⛔ `meson` must be 1.6.0 or newer. An older `meson` does not detect the `zig` linker. It stops at the `pacman` step, after every library is built. The apt `meson` of Ubuntu 24.04 is older than 1.6.0.

On Arch Linux, or in an image of this repository:

```bash
pacman -Syu --noconfirm --needed curl git gnupg make perl pkgconf binutils \
  xz bzip2 gzip meson ninja gperf qemu-user-static jq
```

On Debian or Ubuntu, install `meson` with `scripts/install-tools`. It gets the pinned version and checks its sha256. CI uses the same pin.

```bash
apt-get install -y --no-install-recommends ca-certificates curl git gnupg make \
  perl pkg-config binutils xz-utils bzip2 gzip ninja-build gperf python3 \
  qemu-user-static jq
scripts/install-tools "$HOME/.local/tools" meson
export PATH="$HOME/.local/tools:$PATH"
```

### Build

```bash
WORK=/tmp/pacman-static OUT=/tmp/dist scripts/build-pacman-static "$ARCH"
scripts/build-pacman-static --check-evidence "/tmp/dist/pacman-static-$ARCH.json"
export PACMAN="/tmp/dist/pacman-static-$ARCH"
```

The build does these steps:

1. It reads the target facts from `ports/$ARCH.conf`: the `zig` triple, the autotools host triplet, the OpenSSL target, the ELF machine, the emulator, the `meson` CPU family and the byte order. `scripts/build-pacman-static --describe "$ARCH"` shows them.
2. It downloads each tarball of the pin into `WORK/dl`. The file name is the `sha256`. For each tarball it tries the URL of the record, then each `mirror` line of that record. ⛔ It keeps a file only when the `sha256` equals the pin.
3. It fetches the signed `pacman` tag and checks its object sha. It imports each signer key from `bootstrap/pacman-static/keys/`, then from the keyservers of the pin. It requires a valid signature from a signer of the pin.
4. It builds each library of the pin, in pin order, then `pacman` at the pinned commit.
5. It checks the ELF machine and that there is no `PT_INTERP`. Then it runs `--version` under the emulator.

A second run, or a run for another port, with the same `WORK` downloads nothing again. `scripts/build-pacman-static --fetch` downloads and checks every tarball of the pin, and builds nothing.

zig is unpacked into `WORK/zig-<sha256>`, so a reused `WORK` unpacks the new zig after a pin change. `scripts/build-pacman-static --zig` prints the zig that a build uses and its version. The evidence file records that version.

⚠ With no emulator for the port, the evidence file records `NOT MEASURED` for the run. `--check-evidence` refuses it.

⚠ `PACMAN_TAG_VERIFY=skip` builds with no tag check. The evidence file records `SKIPPED`, and `--check-evidence` refuses it.

The evidence file beside the binary records each source with its version, URL and `sha256`, the `pacman` commit, the tag check and the run:

```bash
jq '{arch, triple, pacman_commit, pacman_tag_verified_by, reported_version, elf_machine, interp_segments, sha256}' \
  "/tmp/dist/pacman-static-$ARCH.json"
```

## Check the binary

```bash
readelf -lW "$PACMAN" | awk '/INTERP/ { n++ } END { print n + 0 }'
"$PACMAN" --version
```

The `INTERP` count must be `0`. Then the binary names no dynamic loader, and it runs on a system with no `libc` or a broken `libc`.

⚠ A binary for another CPU runs only on that CPU, or under `qemu-user` with `binfmt_misc`.

## Build a root

The root needs two passes:

- Pass one installs `base` with no signature check. A static `pacman` cannot check signatures without a keyring, and `pacman-key` is a shell script that needs `gpg` from the new root.
- Pass two runs inside the new root. It populates the keyring and syncs again with the shipped `SigLevel`.

⛔ Pass one checks no package signature. Do not use the root before pass two succeeds.

### Pass one, no signature check

```bash
export ROOT=/tmp/archroot
mkdir -p "$ROOT/var/lib/pacman" "$ROOT/var/cache/pacman/pkg" \
  "$ROOT/etc/pacman.d/hooks" "$ROOT/etc/pacman.d/gnupg" "$ROOT/var/log"
```

⚠ `pacman` makes `--dbpath` and `--cachedir`, but it refuses a `--hookdir` that does not exist.

Write a config outside the root, so that no package in the transaction can change it. Start from the config that built the published image of the port. Set `SigLevel = Never`, and point each `Include` line at the server lists of the port in this repository:

```bash
mkdir -p /tmp/pacboot
sed -e 's|^SigLevel .*|SigLevel = Never|' \
  -e "s|^Include = /etc/pacman.d/|Include = $PWD/rootfs/$ARCH/etc/pacman.d/|" \
  "rootfs/$ARCH/etc/pacman.conf" > /tmp/pacboot/pacman.conf
```

⛔ Give `pacman` all six paths, not only `--root`. `--root` moves only the database, the lock and the log into the root. The config, the cache, the keyring and the hook directory `/etc/pacman.d/hooks` stay at their compiled-in paths on the host.

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

⚠ Install `base`, not a smaller set. Install scriptlets run with the shell of the new root, so a root with no `bash` cannot run them.

Count the installed packages. Do not trust the exit status alone:

```bash
find "$ROOT/var/lib/pacman/local" -mindepth 1 -maxdepth 1 -type d | awk 'END { print NR }'
```

### The keyring

The keyring to populate depends on the port. `ports/$ARCH.conf` names it in the key `keyring`. `none` means `archlinux`. Any other value names a pin in `bootstrap/keyrings/`. The pin gives the keyring package, its `sha256` and its trusted fingerprints, and this repository carries the package.

Install the carried keyring package after a `sha256` check. `keyring` gets a value only when the check passes:

```bash
pin="$(scripts/ports get "$ARCH" keyring)"
keyring=""
if [ "$pin" = none ]; then
  keyring=archlinux
else
  pkg="bootstrap/keyrings/$(awk -F' *= *' '$1 == "package" { print $2 }' "bootstrap/keyrings/$pin.pin")"
  want="$(awk -F' *= *' '$1 == "sha256" { print $2 }' "bootstrap/keyrings/$pin.pin")"
  if [ "$(sha256sum "$pkg" | awk '{ print $1 }')" = "$want" ]; then
    pac -U --noconfirm "$pkg"
    keyring="$pin"
  else
    echo "$pkg does not have the sha256 of its pin" >&2
    false
  fi
fi
echo "keyring: ${keyring:-none, the check failed}"
```

⛔ Do not go on to pass two when the sha256 does not match. For the pins `archpower` and `archlinux-lcpu`, `base` depends on the keyring package. So pass one installed the keyring of a mirror, with no check, and pass two would trust it.

⚠ For `none`, pass one installed `archlinux-keyring` from a mirror with no check. Compare its master key fingerprints with https://archlinux.org/master-keys/ before you trust the root.

### Pass two, with the signature check

⛔ Do not bind mount the `/dev` of the host. If the `umount` fails, an `rm -rf` of the root deletes the device nodes of the host. Make five device nodes:

```bash
mknod -m 666 "$ROOT/dev/null" c 1 3
mknod -m 666 "$ROOT/dev/zero" c 1 5
mknod -m 666 "$ROOT/dev/random" c 1 8
mknod -m 666 "$ROOT/dev/urandom" c 1 9
mknod -m 666 "$ROOT/dev/tty" c 5 0
cp -f /etc/resolv.conf "$ROOT/etc/resolv.conf"
```

Populate the keyring. Install the shipped config and the server lists of the port. Sync again. An empty `keyring` stops the first command:

```bash
chroot "$ROOT" /usr/bin/bash -c "pacman-key --init && pacman-key --populate ${keyring:?no checked keyring}"
cp "rootfs/$ARCH/etc/pacman.conf" "$ROOT/etc/pacman.conf"
cp "rootfs/$ARCH/etc/pacman.d/"mirrorlist* "$ROOT/etc/pacman.d/"
chroot "$ROOT" /usr/bin/bash -c 'pacman -Syu --noconfirm'
```

The shipped config has `SigLevel = Required DatabaseOptional`. When this sync succeeds, the signature check works in the new root.

### Check that the root runs

```bash
chroot "$ROOT" /usr/bin/bash -c 'echo it-runs'
chroot "$ROOT" /usr/bin/pacman --version
```

⭐ This check runs the dynamically linked binaries of the new root with the loader of the new root. The static binary has no part in it.

## Make an image and test it

The image gets the labels and the `/etc/os-release` that a build of the Dockerfile gives. `scripts/gen-evidence` reads the commit and the time from the labels.

```bash
platform="$(scripts/ports get "$ARCH" platform)"
version="$(date -u +%Y.%m.%d)"
bootstrap/any/usr/local/bin/write-os-release "$ROOT" "$version"
tar --numeric-owner -C "$ROOT" -c . | podman import \
  --change "LABEL org.opencontainers.image.version=$version" \
  --change "LABEL org.opencontainers.image.revision=$(git rev-parse HEAD)" \
  --change "LABEL org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  - localhost/archlinux:bootstrapped
scripts/gen-evidence "$ARCH" localhost/archlinux:bootstrapped "$platform" /tmp/ev.json
IMAGE=localhost/archlinux:bootstrapped PLATFORM="$platform" EVIDENCE=/tmp/ev.json \
  tests/run.sh image
```

⚠ `scripts/gen-evidence` reads the current repository databases, because this root has no database snapshot. It stops when a package moved after pass two.

## Repair a system with a broken libc

Start from rescue media. Mount the broken root at `/mnt`.

⛔ `-r /mnt` alone is not enough. It moves only the database, the lock and the log. pacman then reads the config, the keyring, the cache and the hooks of the rescue system. Rescue media with no `/etc/pacman.conf` stops at once: "config file /etc/pacman.conf could not be read".

So give every path. The `Include` lines of the config of the root are absolute, so a copy outside the root points them into `/mnt`. `--hookdir` must exist:

```bash
mkdir -p /tmp/rescue /mnt/etc/pacman.d/hooks
sed 's|^Include = /etc/pacman.d/|Include = /mnt/etc/pacman.d/|' /mnt/etc/pacman.conf > /tmp/rescue/pacman.conf
rp() {
  "$PACMAN" --config /tmp/rescue/pacman.conf --root /mnt \
    --gpgdir /mnt/etc/pacman.d/gnupg --hookdir /mnt/etc/pacman.d/hooks \
    --cachedir /mnt/var/cache/pacman/pkg "$@"
}
rp -S --noconfirm glibc
rp -Qkk
```

⚠ The binary must be for the CPU of the broken system.

## What the binary does not remove

| still necessary | why |
| --- | --- |
| a kernel that runs the binary | the binary is static, not a boot loader |
| `/dev/urandom` | OpenSSL and `gpg` need entropy. Without it they fail in ways that look like a `pacman` fault |
| `/etc/ssl/certs/ca-certificates.crt` | `curl` has this path, not embedded certificates. On a host with no bundle, use an `http` server |
| a server that answers | the binary removes the container image from the trust root, not the network |

## Limits

⚠ `libcurl` in the binary has no brotli and no nghttp2. It uses HTTP/1.1 and does not accept the `br` content encoding. An Arch mirror needs neither. The evidence file records the `curl` features in `curl_features`.

⚠ Each run of a binary for another CPU than the build host is a `qemu-user` run. `qemu-user` emulates the instructions and passes each system call to the host kernel. It does not test the kernel or the page size of the target.

⚠ Nobody has run this guide end to end for every port. `tests/static/80-docs-claims.sh` checks that each command block parses.

## Licences

`pacman` is GPL-2.0-or-later. Each binary also links OpenSSL 3, which is Apache-2.0, so the binary is distributed under GPL-3.0-or-later. [THIRD-PARTY.md](../THIRD-PARTY.md) gives each licence. Four libraries in the binary use the LGPL, version 2.1: libgpg-error, libassuan, gpgme and libseccomp. A release does not carry the source tarballs. `bootstrap/pacman-static/sources.pin` names each source by URL and `sha256`. `scripts/build-pacman-static --fetch` downloads each one into `WORK/dl` and checks it.
