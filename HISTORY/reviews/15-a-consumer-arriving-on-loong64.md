# Review 15: a consumer arriving on loong64

**Lens.** Somebody pulls this image on a LoongArch machine. They have nothing to
compare it against, so nothing can be "unchanged" for them: every default is the
first one they meet. Does the image work as a base, and does anything about it
read as a second class port.

**Date.** 2026-08-28, against `localhost/archlinux:loong64` built from the tree
on this workstation, and against the dry run that pushed the same thing.

⚠ Distinct from review 1, which is a consumer who **upgrades**. This one has no
previous image, so drift is not the question. Working at all is.

---

## What was checked

Everything asked of the image was asked inside it, on `linux/loong64` under
emulation.

### The trust root reaches the consumer, not just the build

```bash
podman run --rm --platform linux/loong64 localhost/archlinux:loong64 \
  gpg --homedir /etc/pacman.d/gnupg --no-permission-warning --batch --with-colons \
      --list-keys A6C02FBE730CD45859B946E15C74AE170BDA1433
```

`validity=f`. ⭐ **The key that signs 260 of the 293 packages in `core` is fully
valid inside the published image**, so the consumer's first `pacman -Syu`
verifies rather than refusing. That is the thing the build proving it can install
does **not** prove: the build host's keyring is thrown away, and the image's is
built separately by `pacman-key --populate` in the final stage.

```bash
podman run --rm --platform linux/loong64 localhost/archlinux:loong64 \
  ls /usr/share/pacman/keyrings/
```

```
archlinux.gpg  archlinux-lcpu.gpg  archlinux-lcpu-revoked  archlinux-lcpu-trusted
archlinux-revoked  archlinux-trusted
```

Both keyrings ship, because `bootstrap/loong64/etc/bootstrap-packages.txt` names
`archlinux-lcpu-keyring` alongside `base`, the way the ARM ports name theirs.

### The two mirrorlists do not collide

```bash
podman run --rm --platform linux/loong64 localhost/archlinux:loong64 \
  sh -c 'ls -la /etc/pacman.d/ | grep mirrorlist; awk "/^\[|^Include/" /etc/pacman.conf'
```

| file | bytes | who wrote it | read by pacman |
| --- | --- | --- | --- |
| `/etc/pacman.d/mirrorlist` | 714 | this repository | ⭐ yes, both `Include` lines name it |
| `/etc/pacman.d/mirrorlist-loong64` | 437 | `pacman-mirrorlist-loong64`, a dependency of `pacman` | no |

⭐ **Confirmed rather than assumed.** `HISTORY/loong64.md` predicted this from the
file names before the port was built. The consumer gets one active list, and a
second one sitting beside it that they can point an `Include` at if they prefer
the port's own ordering.

### Nothing else marks it out

| what | loong64 | the other four |
| --- | --- | --- |
| `/etc/os-release` | `ID=arch`, `VERSION_ID=2026.08.28` | the same |
| packages installed | 137 | 137 on three of them, 135 on riscv64 |
| anchor | `pacman 7.1.0.r9.g54d9411-2` | the same value |
| repositories enabled | `core`, `extra` | `core`, `extra`, plus `alarm` and `aur` on ARM |
| image suite | `6 files, failed: 0`, `35 of 35` on defect parity | the same |
| tags | `loongarch64` and `loong64`, three shapes, two registries | two names each except riscv64 |

---

## What was found and changed

**One thing, and it is not loong64 specific.** The README said `latest` resolves
to "an index over all four platforms". It is five. Two rows of the tag table were
the only user-facing count of architectures in the tree, and a consumer arriving
on the fifth would have read a table that did not include them. Changed to "an
index over every platform", which cannot go stale again.

Carried in review 16, which is where the whole sweep for that count lives.

## What was ruled out

- **A permissions difference.** `/etc/pacman.d/mirrorlist` reads `777` in a
  locally built image and `644` in the published one. Measured on both loong64
  and amd64 locally, and against `docker.io/pkgforge/archlinux:latest`, which is
  `644`. Git records `100644`. ⚠ It is a Windows build host artefact, identical
  on every architecture, and not something this port introduced.
- **A missing keyring in the image.** Present, and the signing key is fully
  valid, measured above.
- **A different `os-release`.** Same `ID` and same `VERSION_ID` shape.
- **A short mirror list.** Six servers, against seven for riscv64 and thirteen
  for the others. Above the `MIN_SERVERS` floor of 2, and all six are the list
  the port itself ships.
- **The consumer contract.** `tests/image/50-consumer-contract.sh` passed on
  loong64 in the local suite and in the dry run, so the eight things
  `pkgforge/devscripts` patches are all present.

## ⚠ What this did not look at

- **A real LoongArch machine.** Everything here ran under QEMU. A defect that
  only appears on real hardware, or one QEMU papers over, would not show.
- **`pacman -Syu` actually completing.** The keyring was checked, and a network
  upgrade inside the image was not run. `HISTORY/loong64.md` records a `base`
  install committing under `SigLevel = Required`, which is the same trust path,
  but not from inside the published image.
- **Whether any loong64 consumer exists.** None was looked for. The port is new
  here and nothing downstream can reference it yet.
- **The `alarm` and `aur` repositories.** loong64 has no equivalent, and no
  attempt was made to find one.
- **Docker Hub.** The dry run's `publish_hub` was false, so only GHCR carried the
  loong64 tags that were inspected.

## Change summary

Files touched: 0. The README rows this review found are counted in review 16,
which swept the whole tree for that count. Counting them twice would make the
two reviews look like more change than there was.
