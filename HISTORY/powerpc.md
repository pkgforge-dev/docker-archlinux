# The three PowerPC ports

Added 2026-08-28. `ppc`, `ppc64` and `ppc64le`, published by ArchPOWER, taking
the architecture set from five to eight.

⛔ Three architectures, not three spellings of one. `ppc` is 32 bit big endian,
`ppc64` is 64 bit big endian and `ppc64le` is little endian. A binary built for
one runs on none of the others.

`HISTORY/removed-architectures.md` carries why they were excluded, and the
2026-08-28 re-measurement that cleared the trust block. This page carries what
was built after that.

## What was decided

The maintainer chose all three on 2026-08-28, over `ppc64le` alone and over the
two 64 bit ports. The cost of the extra two is one matrix entry, one mirrorlist
pair and one `pacman.conf` each: the trust root, the keyring pin and the
repository shape are shared, so the second and third cost far less than the
first.

## The trust root

One pin serves all three. `bootstrap/keyrings/archpower.pin`.

| fact | value |
| --- | --- |
| package | `archpower-keyring-20260408-1-any.pkg.tar.zst` |
| bytes | 28621 |
| sha256 | `2f3ebb1a9234775e9244bf45ae1121a20bdbe7d27efbd440a3da172a2baf6241` |
| primary keys in `archpower.gpg` | 4 |
| trusted in `archpower-trusted` | 3, all at trust level 4 |
| revoked, and absent from the keyring | 1, `3B40CFA2B2FC99268DE7B31BF95FE1C7E212CF15` |
| nearest expiry | 2031-02-22 |

```bash
curl -sSfL --connect-timeout 20 --max-time 300 -o k.pkg.tar.zst \
  https://repo.archlinuxpower.org/base/any/archpower-keyring-20260408-1-any.pkg.tar.zst
sha256sum k.pkg.tar.zst
bsdtar -xOf k.pkg.tar.zst usr/share/pacman/keyrings/archpower-trusted
```

⭐ The keyring package is an `any` architecture package, so it is in `base/any`
and in none of the three architecture databases. That is why the earlier probe
concluded no keyring existed: it read the wrong database.

⚠ No new installer was written. `install-port-keyring` is driven by the `.pin`
files, so adding a port is a file rather than a script, which is what the
loong64 work established.

⚠ This is the one pin with no key inside `scripts/check-keyring-pin`'s one year
warning horizon. Nothing about the port makes that permanent.

## The repository shape, which is unlike every other port

Measured 2026-08-28 against `repo.archlinuxpower.org`.

| difference | what it breaks |
| --- | --- |
| the core equivalent repository is named `base` | `core.db` answers 404, so a resolver that assumes `core` reports every mirror dead |
| there is no `extra` | `extra.db` answers 404, and one 404 fails the whole sync rather than one repository |
| the databases are Zstandard | every other port ships gzip, and the file is named `<repo>.db` in both cases, so nothing announces which |
| `any` architecture packages are in a second database | `base/any/base-any.db`, and `iana-etc` is only there |

```bash
for r in extra extra-any core community; do
  printf '%-12s ' "$r"
  curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 10 --max-time 60 \
    -L "https://repo.archlinuxpower.org/$r/powerpc64le/$r.db"
done
```

All four answer 404.

⛔ Two repository sections, not two `Server` lines. Two `Server` lines under one
repository name are two mirrors of one database. These are two databases, so
`[base]` includes `mirrorlist` and `[base-any]` includes `mirrorlist-any`.
`scripts/gen-mirrorlist` writes both, and writes the second only for a port that
has a `mirrors/<arch>.any-anchors` file, so a port that later does the same
needs the file and no code.

### Database contents

| database | packages |
| --- | --- |
| `base/ppc/base.db` | 3552 |
| `base/ppc64/base.db` | 3533 |
| `base/ppc64le/base.db` | 3736 |
| `base/any/base-any.db` | 2200 |

⚠ **A correction to a studied reference.** `Aseem0xff/pacman-static`
`docs/GOTCHAS.md` G-11 states that `iana-etc` and `openssl` are only in the
`any` database. `iana-etc` is. `openssl` is not: `openssl-3.6.3-1` is in the
architecture specific database, along with `openssl-1.0` and `openssl-1.1`.
Measured 2026-08-28. Its package counts, 3736 and 2200, reproduce exactly.

```bash
tar --zstd -tf base-powerpc64le.db | awk 'index($0, "openssl") == 1'
```

## The anchor

All three resolve, and all three carry the same pacman commit every other port
carries.

| architecture | anchor |
| --- | --- |
| `amd64`, `arm64`, `armv7`, `loong64`, `riscv64` | `7.1.0.r9.g54d9411-2` |
| `ppc`, `ppc64`, `ppc64le` | `7.1.0.r9.g54d9411-2.2` |

⚠ The `pkgrel` differs and the commit does not. The ports have never been in
lockstep on `pkgrel`, which is why the anchor is resolved per architecture.

```bash
for a in amd64 arm64 armv7 loong64 riscv64 ppc ppc64 ppc64le; do
  printf '%-12s %s\n' "$a" "$(scripts/resolve-anchor "$a")"
done
```

⛔ `scripts/resolve-anchor` needed two changes for this and both are general
rather than PowerPC specific. It reads the primary repository name from the
architecture's own `pacman.conf` rather than assuming `core`, and it reads a
database in either compression and says what each one reported when neither
works. `scripts/gen-evidence` and `tests/static/40-mirrors-reachable.sh` take the
same two changes.

⚠ A host with no `zstd` can read five of the eight and not these three. The
message says so by name rather than folding it into "not a readable archive".

## What was built and measured

Every image built on this workstation under QEMU, 2026-08-28, from the tree at
the commit this page ships in.

| architecture | image build | `uname -m` | packages | keys after populate | image suite |
| --- | --- | --- | --- | --- | --- |
| `ppc` | exit 0 | `ppc` | 141 | 5 | 66 of 66 |
| `ppc64` | exit 0 | `ppc64` | 140 | 5 | 66 of 66 |
| `ppc64le` | exit 0 | `ppc64le` | 140 | 5 | 66 of 66 |

⭐ `uname -m` reports the same string as the Docker architecture on all three,
which is not true of `loong64` or of the two ARM ports. That is why each tag set
carries the ArchPOWER spelling as its second name rather than a `uname -m`
alternative: without it there would be one name where every other port has two.

```bash
podman build --platform linux/ppc64le --build-arg "IMAGE_VERSION=$(date -u +%Y.%m.%d)" \
  --build-arg "SOURCE_COMMIT=$(git rev-parse HEAD)" \
  --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -t localhost/archlinux:ppc64le .

SOURCE_COMMIT="$(git rev-parse HEAD)" BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  scripts/gen-evidence ppc64le localhost/archlinux:ppc64le linux/ppc64le /tmp/ev.json
IMAGE=localhost/archlinux:ppc64le PLATFORM=linux/ppc64le EVIDENCE=/tmp/ev.json \
  tests/run.sh image
```

⚠ The evidence run needs a host with `zstd`, so it was run inside the podman
machine rather than on the Windows side. The image build has no such
requirement.

⭐ The evidence file joins against **both** databases, which is the assertion
that the two section arrangement is right rather than merely accepted:

```
base database read from https://repo.archlinuxpower.org/base/powerpc64le/base.db
base-any database read from https://repo.archlinuxpower.org/base/any/base-any.db
```

`scripts/gen-evidence` reads the mirror list each repository section `Include`s,
rather than the default one, which is what makes the second database reachable.

## The two things CI needed that no other port needed

### 1. ⛔ The origin refuses GitHub runners

Measured 2026-08-28 from a runner. Every request to `repo.archlinuxpower.org`
answers **403** with a Cloudflare "Just a moment..." interstitial, 5379 bytes.
It is the source network and not the identity: curl's own user agent, pacman's,
a browser's and this repository's all get the same answer.

| from | user agent | code |
| --- | --- | --- |
| GitHub runner | `curl/8.5.0` | 403 |
| GitHub runner | `pacman/7.1.0` | 403 |
| GitHub runner | `libalpm/16.0.1` | 403 |
| GitHub runner | `Mozilla/5.0` | 403 |
| GitHub runner | `docker-archlinux-mirrorlist/1` | 403 |
| this workstation | any of the above | 200 |

⭐ **Mined 2026-08-29, and it changes what this measurement means.** The
ArchPOWER tracker records the maintainer blocking whole networks deliberately.
Issue 69, closed 2023-12-29, in his own words:

> After careful consideration I blocked all traffic from the Russian Federation

⛔ **So network level blocking is this origin's normal practice, not an
accident.** ⚠ Nothing upstream says GitHub's ranges are blocked and no issue
names a CI runner, so this is a lead and not a diagnosis. What it settles is the
posture: ⛔ the read through proxy is a permanent second path, not a workaround
waiting for upstream to fix a bot rule. `HISTORY/references/kth5-archpower.md`.

⭐ **`api.rv.pkgforge.dev` is a read through proxy in front of the same origin,
and it answers from both.** It returned byte identical databases: 724493 bytes
for `powerpc64le`, 741715 for `powerpc`, 684273 for `powerpc64`, and 504891 for
`base-any`, matching the origin exactly.

```bash
curl -s -o /dev/null -w '%{http_code} %{size_download}
' --connect-timeout 15 --max-time 120   -L https://api.rv.pkgforge.dev/https://repo.archlinuxpower.org/base/powerpc64le/base.db
```

⭐ **It is a second server, not a replacement.** The origin is first in every
list, so a consumer that can reach it uses it and the proxy carries only what
cannot. pacman falls through to the next `Server` on a failed transfer, which is
what makes the ordering do the work.

⚠ **The proxy cannot forge a package.** `SigLevel` stays `Required` and the
keyring is pinned by sha256 and by fingerprint. What a proxy could do is serve a
stale but validly signed set, which is the case `scripts/check-anchor-floor`
already refuses.

⛔ **Three places had to learn to fall through**, and each failed in a different
step before they did:

| place | how it failed |
| --- | --- |
| `scripts/resolve-anchor` | already tried every `Server`, so adding the second entry was enough |
| `bootstrap/any/usr/local/bin/install-port-keyring` | read one `mirror` field and stopped. The build failed at `install-port-keyring`, the first step that touches the network |
| `scripts/check-keyring-pin` | read one `mirror` field to list the directory. The weekly freshness job runs on a runner |

⚠ The checksum is what makes a second transfer path safe rather than a second
trust root: whichever mirror answers, the package has to be the pinned one byte
for byte.

### 2. ⛔ No big endian emulator in the standard setup

`docker/setup-qemu-action` registers no big endian PowerPC emulator, and nothing
in its output says so. Measured 2026-08-28 by listing the filesystem of the
image it runs:

```bash
podman create --name bfx docker.io/tonistiigi/binfmt:latest true
podman export bfx | tar -tf - | grep -i qemu
```

Nine emulators: `qemu-aarch64`, `qemu-arm`, `qemu-i386`, `qemu-loongarch64`,
`qemu-mips64`, `qemu-mips64el`, `qemu-ppc64le`, `qemu-riscv64`, `qemu-s390x`.
Neither `qemu-ppc` nor `qemu-ppc64` is among them.

The last stage of the `Dockerfile` runs `pacman-key` and `locale-gen` as target
architecture binaries, so without a handler those two jobs fail on `exec format
error` after a build that already downloaded every package.

⛔ **Ubuntu's `qemu-user-static` is not the fix, and trying it cost a run.** It
ships the emulators and no binfmt descriptions: `/usr/share/binfmts` holds one
entry, `python3.13`, and `update-binfmts --import qemu-ppc` answers "couldn't
find information about 'qemu-ppc' to import" and exits 2. Confirmed in a Debian
trixie container as well as on the runner.

`build-deploy.yml` runs `multiarch/qemu-user-static`, pinned by digest, for
those two jobs only, and then asserts the handler exists and carries the `F`
flag. ⚠ Without `F` the kernel opens the interpreter inside the build container,
where the emulator is not present.

### What that produced

Dry run `33195922986`, 2026-08-28, eight architectures on a branch:

```
Resolve inputs success
Build amd64 success      Build arm64 success     Build armv7 success
Build loong64 success    Build riscv64 success
Build ppc success        Build ppc64 success     Build ppc64le success
Create tags success
```

The scratch index carries `amd64 arm64 armv7 loong64 ppc ppc64 ppc64le riscv64`.
End to end: 456 seconds, against 416 for five architectures.

⚠ **The run before it failed and is the more useful record.** `33194671836` had
`Resolve inputs` succeed through the proxy and all three PowerPC builds fail:
`ppc64le` on `install-port-keyring` fetching the keyring from the origin, and
`ppc` and `ppc64` on the apt route to the emulators. Both were fixed by the
measurements above rather than by retrying.

⚠ This workstation needed neither: its `binfmt_misc` already carries `qemu-ppc`,
`qemu-ppc64` and `qemu-ppc64le`, and it reaches the origin directly. That is why
both gaps had to be measured against CI rather than noticed by a failing build
here.

## What is not proven

- ⚠ **Real hardware.** Nothing has run on a PowerPC machine. Every measurement
  here is `qemu-user`, which emulates the instruction set and passes syscalls to
  the host kernel. It does not exercise the target's kernel, and 64 K pages on a
  real ppc64 host are exactly where a static binary's segment alignment bites.
- ⚠ **One publisher.** `repo.archlinuxpower.org` is the only host that publishes
  these packages. There is no `pacman-mirrorlist` package among the 2200 in
  `base/any`, and neither `archlinuxpower.org` nor `kth5/archpower` names another
  server. ⛔ The proxy beside it is a second transfer path in front of the same
  origin, not a second publisher, so the single point of failure is unchanged.
  TODO 6.
- ⚠ **The proxy is now a dependency.** `api.rv.pkgforge.dev` going away takes
  every PowerPC build on a runner with it, and nothing watches it. It cannot
  serve a forged package, because `SigLevel` stays `Required` and the keyring is
  pinned, and it can serve a stale one, which `scripts/check-anchor-floor`
  refuses.
- ⚠ **No published tag.** These three have never been through a real publish.
  The images in the table were built here.
- ⚠ **`kth5/archpower` is not mined.** Policy 11 has not been applied to it, and
  it is where a change to the repository layout would appear first.
