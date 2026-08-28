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

## The port, as built

⭐ **Added 2026-08-28.** Five architectures now, not four.

### The trust root, and why the installer was generalised

⛔ **The ARM pin format does not transfer.** It carries one `master` fingerprint
and that keyring has one key. This one lists ten, and two of them are already
expired. A second installer differing from the first only by a name is the shape
that rots, so there is one installer and one pin format, and adding a port is a
`.pin` file rather than a script.

`bootstrap/any/usr/local/bin/install-port-keyring` reads every
`bootstrap/keyrings/*.pin`, and uses the one whose `arch` list carries the
`Architecture` of the build. amd64 and riscv64 match nothing and it exits 0
having touched no keyring.

Each pin holds the keyring name, the architectures it serves, the mirror, the
package, its sha256, and one `trusted` line per fingerprint carrying that key's
**expiry**. Both halves are asserted:

| assertion | what it catches |
| --- | --- |
| sha256 of the fetched package | the mirror serving different bytes |
| the trusted fingerprint set, whole | a signer added or removed |
| each key's expiry against the pin | the key material moving |
| after populate, every key the pin dates in the future is `f` or `u` | ⛔ the `i686` failure: a keyring that installs and then verifies nothing |
| at least one key usable at all | the day the last one lapses |

⭐ **Validity, not presence, is the assertion that matters.** `i686` had its
keyring installed and still committed nothing, because a signer sat below full
validity. A check that only asked whether the fingerprint was present would have
passed there.

⚠ **A key past its pinned expiry is named and skipped, not fatal.** It can sign
nothing pacman will take, and refusing a build for a key that signs nothing would
refuse a build that works. `HISTORY/loong64.md` measures that neither expired key
signs any of the 293 packages in `core`.

### Two spellings, so two tag names

```bash
podman image inspect localhost/archlinux:loong64 --format '{{.Architecture}}'
podman run --rm --platform linux/loong64 localhost/archlinux:loong64 uname -m
```

`loong64` and `loongarch64`. The alias set is `loongarch64 loong64`, the
`uname -m` spelling first, which is the order `scripts/tag-names` already uses.
Twelve tags per build, two aliases times three shapes on two registries.

### The mirrors

`mirrors/loong64.anchors` carries one server and `mirrors/loong64.pool` the other
five. All six are the list the port ships as `pacman-mirrorlist-loong64`, and all
six served the same 90776 byte `core.db` when the list was generated.

⛔ **`mirrors.pku.edu.cn` cannot be the anchor.** It serves files, and answers a
directory with a JavaScript single page application, so a text scan of its
listing finds nothing:

```bash
curl -sS -L https://mirrors.pku.edu.cn/loongarch/archlinux/core/os/loong64/ | wc -c
curl -sS -o /dev/null -w '%{http_code} %{size_download}\n' -L \
  https://mirrors.pku.edu.cn/loongarch/archlinux/core/os/loong64/archlinux-lcpu-keyring-20241126-1-any.pkg.tar.zst
```

597 bytes of HTML for the directory, and `200 15627` for the file inside it.
`scripts/check-keyring-pin` lists a directory, so the anchor is
`loongarchlinux.lcpu.dev`, which serves a plain index.

### Everywhere the architecture set is named

⭐ **The set was not listed by hand.** Adding the matrix entry first and running
`bash tests/run.sh static` made `tests/static/75-architecture-set.sh` report
`failed 17 of 24`, naming 14 sites in 6 files plus the four missing per
architecture files. Each edit turned one line green.

⚠ **One site needed the docker platform spelling rather than the matrix key.**
The index verification in `build-deploy.yml` compares against
`amd64 arm64 loong64 riscv64 arm/v7`, because `armv7` renders as `arm/v7` there.

### What became data instead of a list

| was | is |
| --- | --- |
| `install-alarm-keyring`, ARM only, one master fingerprint | `install-port-keyring`, any port, driven by `bootstrap/keyrings/*.pin` |
| `check-keyring-pin`, one hardcoded pin and mirror | takes a pin, or checks every pin |
| `90-package-lists.sh`, a hardcoded `arm64 armv7` loop | derives the pairs from the pins and the shipped `pacman.conf` files |
| `freshness-keyring.yml`, one job | one job per pin, each building the architecture that exercises it |
| `freshness-mirrors.yml`, `mirrors/riscv64.pool` by name | every `mirrors/*.pool`, architecture read from that port's `pacman.conf` |

⭐ **`scripts/check-anchor-floor` needed no edit at all.** It takes its
architecture set from the JSON it is handed, and reported `no floor  loong64
nothing published yet` on the first run that included it.

## What CI proved

Dry run `33165970427`, 2026-08-28, on branch `loong64`. Seven jobs, all green,
six minutes and fifty six seconds end to end.

```bash
gh run view 33165970427 --json status,conclusion,jobs \
  --jq '"run: \(.status)/\(.conclusion)", (.jobs[] | "\(.name) \(.status)/\(.conclusion)")'
```

⛔ **The one measurement the feasibility work could not take is now taken.**
`docker/setup-qemu-action` does register a `loongarch64` handler on
`ubuntu-latest`. The `Build loong64` job ran the emulated stage without a
binfmt error, in 4 minutes 25 seconds, the longest of the five.

| what | value |
| --- | --- |
| keyring step in CI | `8 of 10 pinned keys are fully valid, SigLevel stays Required` |
| packages recorded | 137 |
| anchor | `pacman 7.1.0.r9.g54d9411-2`, the same as the other four |
| per architecture tags created | 6 on GHCR, `loongarch64` and `loong64` times three shapes |
| index platforms after publishing | `amd64 arm/v7 arm64 loong64 riscv64` |

The image suite ran against what was pushed and passed, on loong64 as on the
other four. Locally it reports `passed 35 of 35` for
`tests/image/60-defect-parity.sh` against a `linux/loong64` build.

## What is still not settled

- ⚠ **Nothing is measured about mirror stability over time.** All six answered
  on 2026-08-28. `.github/workflows/freshness-mirrors.yml` now probes
  `mirrors/loong64.pool` monthly along with the others, which is what will
  produce that history.
- ⚠ **One trusted key expires 2027-11-26**,
  `B955F2012D6A161F6D9076AF34BE2B6F4A99C0E9`. When it does, the count of usable
  keys falls from 8 to 7 with no upstream change at all.
  `scripts/check-keyring-pin` reports every key expiring within a year, and the
  weekly job raises a warning annotation for it.
- ⚠ **The organisation precedent for the alias family is still unchecked.**
  `pkgforge/alpine` supports only the `uname -m` family, and the docker-arch
  names are this repository's extension. The set follows this repository's own
  rule, not a sibling image's.
- ⚠ **The fingerprints are still corroborated only by the two keyservers and the
  five mirrors recorded above.** Nothing in this port's own infrastructure
  publishes them independently: the wiki page the signing key's uid names still
  answers 530.
- ⚠ **No loong64 image is published yet.** The dry run wrote to
  `ghcr.io/pkgforge-dev/archlinux-ci`. The first real tags appear on the next
  scheduled publish.

## Beyond the trust half, measured 2026-08-29

⛔ **What was open**: every loong64 measurement was QEMU, and the transfer half
had never been run from inside a published image. The trust half was checked in
`HISTORY/reviews/15-a-consumer-arriving-on-loong64.md`: the lcpu signing key
comes out of the image at `validity=f`. Whether the six shipped mirrors serve a
whole transaction, rather than just `core.db`, was not.

⭐ **It needed a published loong64 tag, and the 2026-08-28 publish created one.**

### The databases sync

```bash
podman run --rm --platform linux/loong64 ghcr.io/pkgforge-dev/archlinux:loong64 \
  sh -c 'pacman -Syu --noconfirm'
```

```
:: Synchronizing package databases...
 core downloading...
 extra downloading...
:: Starting full system upgrade...
 there is nothing to do
```

⚠ **That proves less than it looks.** Both databases transferred from the
shipped mirror list, and then nothing was installed, because the image was built
the same day. ⛔ A green `pacman -Syu` on a current image does not exercise the
package payload path at all.

### A package actually transfers, and its signature is checked

```bash
podman run --rm --platform linux/loong64 ghcr.io/pkgforge-dev/archlinux:loong64 \
  sh -c 'pacman -Sy --noconfirm --needed tree && tree --version && pacman -Q tree'
```

```
 tree-2.3.2-1-loong64 downloading...
checking keyring...
checking package integrity...
:: Processing package changes...
installing tree...
:: Running post-transaction hooks...
(1/3) Arming ConditionNeedsUpdate...
(2/3) Linking executables installed outside PATH...
(3/3) Cleaning up package cache...
tree v2.3.2 (c) 1996 - 2026 by Steve Baker, Thomas Moore, Francesc Rocher, Florian Sesser, Kyosuke Tokoro
tree 2.3.2-1
```

⭐ **Four things at once, and each was separately unproven:**

| | |
| --- | --- |
| a package payload transfers from a shipped mirror | `tree-2.3.2-1-loong64 downloading...` |
| its signature verifies under `SigLevel = Required` | `checking keyring`, `checking package integrity` |
| the installed binary runs under emulation | `tree v2.3.2` |
| all three shipped hooks fire on a consumer's transaction | the `(1/3)` to `(3/3)` block |

⚠ **The second hook is this repository's own.** `Linking executables installed
outside PATH` is the fix for upstream issue 80, Completed row 17. This is the
first time it has been seen running inside a published image on this port
rather than in a test.

⛔ **Still qemu-user.** No target kernel and no target page size. Real hardware
remains untouched and is the one item emulation cannot answer.

## The keyring pin, re-measured 2026-08-29

⚠ **Two claims carried forward from the 2026-08-28 session were wrong**, and the
correction is what `scripts/check-keyring-pin` prints:

```bash
scripts/check-keyring-pin bootstrap/keyrings/archlinux-lcpu.pin
```

```
pinned trusted : 10 fingerprint(s)
expired today  : 5CDE9ADCBD04454BAF547A1C40D0304E1192746B(2026-04-24) 60922C5D40F6297BC1616C270A8F993ECADF8CE7(2026-07-14)
expiring < 1y  : none
result: current
```

| the claim | what is measured |
| --- | --- |
| eight trusted keys | **ten** |
| one key expires 2027-11-26, taking usable keys from 8 to 7 | that key is real and does expire then, but **two others expired already**, on 2026-04-24 and 2026-07-14 |

⭐ **The port is unaffected and that is the point of the pin.** `result: current`
and the build works: the keys that signed the packages this image installs are
not the expired ones. ⚠ What changed is the margin, and nothing had said so.

### The expiry annotation, forced and seen

⛔ **Nobody had seen the warning fire.** `expiring < 1y` is empty because
2027-11-26 is beyond the 365 day horizon, so the branch that raises the
annotation had never been taken. Forced against a scratch copy of the pin with
that key's date moved inside the horizon:

```bash
cp bootstrap/keyrings/archlinux-lcpu.pin /tmp/scratch.pin
sed -i 's/B955F2012D6A161F6D9076AF34BE2B6F4A99C0E9 2027-11-26/B955F2012D6A161F6D9076AF34BE2B6F4A99C0E9 2027-03-15/' /tmp/scratch.pin
scripts/check-keyring-pin /tmp/scratch.pin
```

```
expiring < 1y  : B955F2012D6A161F6D9076AF34BE2B6F4A99C0E9(2027-03-15)
```

Fed to the workflow's own branch from `.github/workflows/freshness-keyring.yml`:

```
::warning::archlinux-lcpu has trusted keys expiring within a year: B955F2012D6A161F6D9076AF34BE2B6F4A99C0E9(2027-03-15)
```

⚠ **The annotation was produced by running the workflow's condition against the
script's real output, not by running the workflow.** The scratch pin was never
committed and no run was dispatched for it.
