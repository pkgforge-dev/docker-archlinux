# loong64

Whether this port can be added, measured before anything is written for it.
Two questions: may signature checking stay on, and does the build run.

⛔ **The gate, taken first.** `ppc64le` was
refused because its signing key could not be verified independently, so
`SigLevel = Required` could not stay on. `i686` was refused later and for a
different reason: it had a keyring, and one signer still sat at marginal
validity, so nothing installed. Both are in
[`removed-architectures.md`](removed-architectures.md).

This records whether `loong64` clears both bars. Measured 2026-08-28. Every
command here ran in `docker.io/pkgforge/archlinux:latest` on `linux/amd64`.

## The criterion

Taken from [`removed-architectures.md`](removed-architectures.md), unchanged:

> a keyring obtainable independently of the packages it signs. A keyring package
> in the repository, a fingerprint published on a channel this repository does
> not fetch packages from, or a signature chaining to a key already in
> `archlinux-keyring`.

⛔ And the bar `i686` set: a keyring that installs is not enough. The
transaction has to commit.

## What the port publishes

```bash
curl -sS -o core.db --connect-timeout 15 --max-time 120 \
  -L https://mirrors.pku.edu.cn/loongarch/archlinux/core/os/loong64/core.db
tar -tzf core.db | awk -F/ 'NF > 1 { print $1 }' | sort -u | wc -l
```

| fact | value |
| --- | --- |
| packages in `core` | 293 |
| packages in `extra` | 14050 |
| `pacman` | `7.1.0.r9.g54d9411-2` |
| `base` | `3-3`, resolving to 137 packages |
| keyring package | `archlinux-lcpu-keyring-20241126-1-any.pkg.tar.zst`, 15627 bytes |
| sha256 | `cfdd65dceddbc5824df091787bd8546143beae9adb12f8ecccc25fbb67baa303` |
| keys in that keyring | 21, of which 10 are listed trusted |
| `core.db.sig` | 404, so the database is unsigned and `DatabaseOptional` applies |
| mirrors answering `core.db` with 200 | 5 of 5, all https |

⭐ **The `pacman` version is the anchor this repository already publishes.**
`7.1.0.r9.g54d9411-2` is the value in the existing `<arch>-<anchor>` tag family,
so this port and the other four would carry one anchor.

## The trust root is self-referential

```bash
gpg --list-packets archlinux-lcpu-keyring-20241126-1-any.pkg.tar.zst.sig
```

| what | key |
| --- | --- |
| signs the keyring package | `8C7F6B7B9B90AE02C2ACB633F0647F18A79089C9`, Zhou Qiankang, who is also its `%PACKAGER%` |
| signs `pacman` and `bash` | `A6C02FBE730CD45859B946E15C74AE170BDA1433`, Linux Club of Peking University |

⛔ **Both keys are inside the keyring they authenticate.** To trust the keyring
you must already trust a key only the keyring supplies.

⛔ **There is no chain to `archlinux-keyring`.** The official keyring carries 489
keys and this one carries 21. The overlap is empty:

```bash
comm -12 official-fprs.txt lcpu-fprs.txt   # prints nothing
```

So the third route in the criterion is closed. The first is open, because a
keyring package exists. The rest of this file measures the second.

## Corroboration from outside the mirrors

### Five mirrors, byte identical

Five servers run by five institutions serve the same keyring package:

```bash
for m in https://mirrors.pku.edu.cn/loongarch/archlinux \
         https://mirrors.nju.edu.cn/loongarch/archlinux \
         https://mirrors.wsyu.edu.cn/loongarch/archlinux \
         https://mirror.iscas.ac.cn/loongarch/archlinux \
         https://loongarchlinux.lcpu.dev/loongarch/archlinux; do
  curl -sS -o k --connect-timeout 15 --max-time 120 \
    -L "$m/core/os/loong64/archlinux-lcpu-keyring-20241126-1-any.pkg.tar.zst"
  sha256sum k
done
```

All five return `cfdd65dc...`. ⚠ That rules out one tampered mirror. It does not
rule out a tampered origin, because they may all sync from one.

### Two keyservers, which are not mirrors

```bash
curl -sS --connect-timeout 20 --max-time 60 \
  "https://keys.openpgp.org/vks/v1/by-fingerprint/$FPR"
curl -sS --connect-timeout 20 --max-time 60 \
  "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$FPR"
```

| key | mirror | keys.openpgp.org | keyserver.ubuntu.com |
| --- | --- | --- | --- |
| `A6C02FBE...`, signs the packages | primary and subkey | ⭐ same primary and subkey, **1 uid** | same primary and subkey, 1 uid |
| `8C7F6B7B...`, signs the keyring | primary and subkey | same primary and subkey, **0 uids** | same primary and subkey, 5 uids |

The subkey fingerprints match too, `CB9750624CFBCDAFCD0A63D92B24E776A1D39283`
and `A399416A958CBF235E945D6B9AB5689B2BC61DA2`.

⭐ **The uid count is the part that carries weight.** keys.openpgp.org publishes
identity only after the address holder answers a confirmation mail. The
package-signing key has a uid there, so somebody holding `linuxclub@pku.edu.cn`
confirmed it. keyserver.ubuntu.com verifies nothing and anyone may upload to it,
so its value here is only that it is a third independent copy of the same bytes.

⚠ **State plainly what this does and does not prove.** It does not prove the key
belongs to the people who run the port. It proves the key material is not
something one mirror produced for this repository, and that it existed on
infrastructure this repository does not fetch packages from.

⛔ **One source did not answer.** The package-signing key's own uid names
`https://lcpu.club/wiki/index.php?title=Publickey`. That page returns **530**,
17 bytes. The channel the key itself points at for verification is down, and it
is not counted above.

```bash
curl -sS -o /dev/null -w '%{http_code}\n' --connect-timeout 20 --max-time 90 \
  -L 'https://lcpu.club/wiki/index.php?title=Publickey'
```

## The bootstrap, which is the real test

⛔ `i686` reached this point and failed. Nothing short of a real transaction
shows whether the trust path holds.

The keyring installs the way `install-alarm-keyring` installs the ARM one, then
`pacman-key --populate archlinux archlinux-lcpu`, then a `base` install into an
empty root with `Architecture = loong64` and `SigLevel = Required`.

### Validity of the ten trusted keys

| validity | count | keys |
| --- | --- | --- |
| full | 8 | including both signers above |
| expired | 2 | `60922C5D40F6297BC1616C270A8F993ECADF8CE7`, `5CDE9ADCBD04454BAF547A1C40D0304E1192746B` |

⚠ Two expired trusted keys is the shape that refused `i686`. It does not bite
here, and the next section is why.

### The transaction

```bash
pacman -r /target -Sy --noconfirm base
```

| result | value |
| --- | --- |
| `pacman` exit | **0** |
| packages installed | 137 |
| files in the root | 23405 |
| `/target/usr/bin/bash` | `ELF 64-bit LSB pie executable, LoongArch, version 1 (SYSV)` |

⭐ **The root is real and it is LoongArch.** No signature was weakened to get
it. `SigLevel = Required` was set for the whole transaction.

## Who signs what

Every `.sig` in `core`, 293 of 293 fetched:

| signer | packages | validity |
| --- | --- | --- |
| `A6C02FBE730CD45859B946E15C74AE170BDA1433` | 260 | full |
| `E340D891C0227DFF3D622A74023DA348C36B0A11` | 26 | full, a subkey of `7A9B819083ED51654DED13C9717A69D3E5AF9CBB` |
| `8C7F6B7B9B90AE02C2ACB633F0647F18A79089C9` | 6 | full |
| `65D4986C7904C6DBF2C4DD9A4E4E02B70BA5C468` | 1 | full |

⭐ **Neither expired key signs a single package in `core`.** That is measured,
not assumed:

```bash
for e in 60922C5D40F6297BC1616C270A8F993ECADF8CE7 5CDE9ADCBD04454BAF547A1C40D0304E1192746B; do
  for s in sigs/*.sig; do gpg --list-packets "$s" | grep -c "issuer fpr v4 $e"; done |
    awk '{ t += $1 } END { print t + 0 }'
done
```

Both print `0`.

⚠ **This is the thing to watch.** The port has two expired keys in its trusted
list. The day a package is signed by one, the transaction stops the way `i686`
does. Whatever watches the pin has to check validity, not only the checksum.

## Two open questions from the brief, now measured

⭐ **The second `Include` is not needed.** The port ships its mirrors as
`pacman-mirrorlist-loong64`, and that package writes
`/etc/pacman.d/mirrorlist-loong64`. The name differs from the stock
`/etc/pacman.d/mirrorlist`, so there is no collision to avoid. The bootstrap
above used one `Include = /etc/pacman.d/mirrorlist` and installed 137 packages.

⚠ `pacman` **depends on** `pacman-mirrorlist-loong64`, so that file lands in any
image built from this port whether or not anything reads it. Upstream's
`pacman-mirrorlist` is in `core` at `20260610-1` and `base` does **not** pull it
in, so `/etc/pacman.d/mirrorlist` stays this repository's to write, exactly as
for the other four architectures.

```bash
pacman -r /t -Sp --print-format '%n' base | grep mirrorlist
# pacman-mirrorlist-loong64
```

⚠ The shipped list names six endpoints, one more than the five probed:
`https://mirrors.pku.edu.cn/loongarch-lcpu/archlinux`.

## The build runs, emulated

⛔ The Dockerfile bootstraps on the builder's own architecture and only the last
stage is emulated. What matters is whether QEMU runs `pacman-key --init` and
`locale-gen` for this target, because a failure there lands four steps into a
build.

A probe mirroring both stages of the real `Dockerfile`, `FROM --platform=$BUILDPLATFORM`
for the bootstrap and `FROM scratch` for the target:

```bash
podman build --platform linux/loong64 -f Containerfile.loong64 -t localhost/loong64-probe:test .
```

| step, all of it emulated | result |
| --- | --- |
| `pacman-key --init` | runs |
| `pacman-key --populate` | runs, locally signs 15 keys, disables 38 revoked |
| `locale-gen` | generates `en_US.UTF-8`, and `locale -a` lists `en_US.utf8` |
| `pacman -Q pacman` | `7.1.0.r9.g54d9411-2` |
| the build | ⭐ **exits 0 and commits an image** |

⚠ Measured on this workstation, where the podman machine registers
`qemu-loongarch64` in `binfmt_misc` and ships `/usr/bin/qemu-loongarch64-static`.
⛔ Whether `docker/setup-qemu-action` registers the same handler on a GitHub
runner is **not** measured here, and is the one thing left before the matrix is
wired.

## The two spellings, confirmed by running it

```bash
podman image inspect localhost/loong64-probe:test --format '{{.Architecture}}'
podman run --rm --platform linux/loong64 localhost/loong64-probe:test uname -m
```

| spelling | value |
| --- | --- |
| the OCI platform string, and what the image records | `loong64` |
| `uname -m` inside the image | `loongarch64` |

⭐ **So this port has two names like the others, not one like riscv64.**
Decision 4 publishes both families, which makes the alias set `loongarch64`
then `loong64`, the `uname -m` spelling first, exactly as
`scripts/tag-names` orders the other three.

## Verdict

⭐ **Both questions pass.** Signature checking stays on: a keyring package
exists in the repository and the fingerprints are published on channels this
repository does not fetch packages from, which is two of the criterion's three
routes. The `i686` bar is met by a transaction that commits 137 packages under
`SigLevel = Required`. And the build runs, producing a `loong64` image whose
`pacman` is the anchor this repository already publishes.

⛔ **What that does not mean.** It does not mean the port is added. It means the
reasons to refuse it are gone. Everything in section 1a of the brief after step
1 is still owed, and the probe above is not repository content.

## What this file does not settle

- ⛔ **`docker/setup-qemu-action` on a GitHub runner is unverified.** The
  emulation above is this workstation's. That is the last measurement before the
  matrix is wired, and it fails loudly rather than silently, so it can be taken
  on a branch.
- ⛔ **`lcpu-club/loongarchlinux-dockerfile` is not yet mined.** Policy 11
  applies before anything is written, and policy 8 forbids bootstrapping from
  the image it builds.
- ⚠ **A pin format is not chosen.** The ARM pin carries one `master`
  fingerprint. This keyring lists ten, two of them expired, so a single-master
  pin does not transfer unchanged.
- ⚠ **The organisation precedent for the alias family is unchecked.**
  `pkgforge/alpine` supports only the `uname -m` family, and the docker-arch
  names are this repository's extension. The set above follows this
  repository's own rule, not a sibling image's.
- ⚠ **Nothing was measured about mirror stability over time.** All five mirrors
  answered on one day. `mirrors/loong64.anchors` and the monthly freshness job
  are what would watch that, and neither exists yet.
