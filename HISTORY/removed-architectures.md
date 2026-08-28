# ppc64le and 386

⚠ **Scratch paths in this document** name fixtures under `.tmp/`, which is
gitignored and wiped between sessions. They record what a measurement was
taken against, not something a reader can open. ⛔ Nothing in the
repository depends on them. To re-run one, copy the tree to a scratch
directory, rebuild the fixture the surrounding text describes, and point the
command at that copy.

`ppc64le` was removed in `9d1e142` and `386` in `e1e99fc`. Requirement: confirm
with evidence that a removed architecture cannot build before leaving it out.
"It was removed" is not evidence. Measured 2026-08-26.

## Upstream ports are live

```bash
curl -s -o /dev/null -w '%{http_code}\n' -L 'https://repo.archlinuxpower.org/base/powerpc64le/base.db'
curl -s -o /dev/null -w '%{http_code}\n' -L 'https://mirror.archlinux32.org/i686/core/core.db'
```

| port | endpoint | status |
| --- | --- | --- |
| ArchPOWER, powerpc64le | `https://repo.archlinuxpower.org/base/powerpc64le/base.db` | 200 |
| Arch Linux 32, i686 | `https://mirror.archlinux32.org/i686/core/core.db` | 200 |

Both platforms also run on the build host under emulation:

```bash
podman run --rm --platform linux/386 alpine uname -m       # x86_64
podman run --rm --platform linux/ppc64le alpine uname -m   # ppc64le
```

## powerpc64le: blocked on a trust root

⛔ **Superseded 2026-08-28. All three PowerPC ports are implemented and this
section is kept for the measurement, not for the verdict.** `ppc`, `ppc64` and
`ppc64le` are in the build matrix, each builds under emulation, and each passes
66 of 66 image assertions. `HISTORY/powerpc.md`.

⚠ Read on for how the exclusion was reached. The two paragraphs below the table
that say no keyring exists were measured against the wrong database, and the
re-measurement that corrects them is further down this page.

⛔ `SigLevel = Required` stays on and policy 5 forbids weakening it. That needs
the signing key in the keyring before any package is installed.

Measured:

| fact | value |
| --- | --- |
| repositories published for `powerpc64le` | `base` 200, `testing` 200, `core` 404, `extra` 404 |
| entries in `base.db` | 7472 |
| `base` package | `base-4-4.2` |
| `pacman` package | `pacman-7.1.0.r9.g54d9411-2.2` |
| keyring package in `base` or `testing` | none. `gnome-keyring` and `libgnome-keyring` are the only matches for the word |
| packages carry a detached signature | yes, `bash-5.3.15-1-powerpc64le.pkg.tar.zst.sig` answers 200 |
| `%PGPSIG%` in the database entry | absent, so the signature is fetched as a separate file |
| key that signed it | `D201F92AE42528456537C3F9B96775F34689694C`, key id `B96775F34689694C` |
| that key in `archlinux-keyring` | no |

⛔ **The key was not found in a form that can be verified independently.** Four
candidate locations were probed and none served a keyring:

```bash
for u in https://archlinuxpower.org/archpower.gpg \
         https://repo.archlinuxpower.org/archpower.gpg \
         https://gitlab.com/archpower/archpower-keyring \
         https://github.com/archpower/archpower-keyring; do
  echo "$(curl -s -o /dev/null -w '%{http_code}' -L "$u") $u"
done
```

404, 404, 403, 404.

⚠ **The fingerprint above was read out of a signature this repository
downloaded, so it cannot be used as the trust root.** Pinning a key taken from
the artefact it signs verifies nothing: anything able to substitute the package
can substitute the signature with it.

⭐ **What would unblock it**, and nothing less: a keyring obtainable
independently of the packages it signs. A keyring package in the repository, a
fingerprint published on a channel this repository does not fetch packages from,
or a signature chaining to a key already in `archlinux-keyring`.

⚠ Also noted, because it breaks an assumption elsewhere: ArchPOWER's database is
Zstandard compressed, where every other port this repository reads ships a gzip
`core.db`. `scripts/resolve-anchor` reads gzip only and would need to detect the
compression before this port could be anchored.

**Verdict: excluded, with the reason recorded.** Not because it was removed
before, and not because the port is inactive. It is excluded because signature
verification cannot be established without weakening `SigLevel`.

### ⭐ Re-measured 2026-08-28: the keyring exists, and the verdict above no longer holds

⛔ **The measurement above looked in the wrong database.** It probed `base` and
`testing` for `powerpc64le` and found no keyring package. `archpower-keyring`
is an `any` architecture package, and ArchPOWER splits arch specific from `any`
packages into **separate** databases. The keyring is in `base/any`, which that
probe never read.

```bash
curl -s -L "https://repo.archlinuxpower.org/base/any/" |
  grep -oE '[a-z0-9._+-]*keyring[a-z0-9._+-]*\.pkg\.tar\.[a-z]+' | LC_ALL=C sort -u
```

`archpower-keyring-20260408-1-any.pkg.tar.zst`, and `python-keyring`.

| fact | value |
| --- | --- |
| package | `archpower-keyring-20260408-1-any.pkg.tar.zst` |
| HTTP, bytes | 200, 28621 |
| sha256 | `2f3ebb1a9234775e9244bf45ae1121a20bdbe7d27efbd440a3da172a2baf6241` |
| detached signature | 200, 119 bytes |
| `pkgdesc` | `Arch POWER PGP keyring` |
| keys in `archpower.gpg` | 7 |
| trusted master keys, `archpower-trusted` | 3, all at trust level 4 |
| revoked, `archpower-revoked` | 1, `3B40CFA2B2FC99268DE7B31BF95FE1C7E212CF15` |

⭐ **It carries the key this page could not verify.**
`D201F92AE42528456537C3F9B96775F34689694C`, recorded above as the key that
signed `bash-5.3.15-1-powerpc64le.pkg.tar.zst` and as not present in
`archlinux-keyring`, is one of the three at trust level 4.

```bash
podman run --rm -i --platform linux/amd64 docker.io/pkgforge/archlinux:latest bash -c '
  cat > /tmp/k.pkg.tar.zst; mkdir -p /tmp/x
  tar --no-same-owner -xf /tmp/k.pkg.tar.zst -C /tmp/x
  cat /tmp/x/usr/share/pacman/keyrings/archpower-trusted' < archpower-keyring.pkg.tar.zst
```

```
8D3D6CE8D4F0625F4D7109022205B7A06C2656A3:4:
D201F92AE42528456537C3F9B96775F34689694C:4:
DE9D1B4851C66CCD9994459CFBB374D5D026D9DA:4:
```

⭐ **By this page's own criterion the block is cleared.** It reads: "a keyring
obtainable independently of the packages it signs. A keyring package in the
repository, a fingerprint published on a channel this repository does not fetch
packages from, or a signature chaining to a key already in
`archlinux-keyring`." The first of the three now exists, and it is the same
shape as `archlinuxarm-keyring` and `archlinux-lcpu-keyring`, both of which
this repository already pins under `bootstrap/keyrings/`.

⚠ **Cleared is not implemented, and three obstacles named elsewhere are
untouched by this.** None is a trust problem.

1. `scripts/resolve-anchor` reads gzip only, and ArchPOWER's databases are
   Zstandard. That is stated above and is unchanged.
2. `repo.archlinuxpower.org` is one host, so there is no second mirror.
3. ArchPOWER needs **two** repository sections rather than one, because `base`
   is unsatisfiable without `base-any`. `iana-etc` and `openssl` are only in
   the second.

⚠ **What was not measured.** No keyring was installed, no `pacman-key
--populate archpower` was run, and no package signature was verified against
it. Everything above is the package's contents read out of the archive. The
bootstrap is what settles it, the way `loong64` was settled.

⚠ **Found while mining an unrelated reference**, whose `docs/GOTCHAS.md` G-11
names `archpower-keyring` and so contradicted this page.
`HISTORY/references/aseem-pacman-static.md`.

### ⭐ Implemented 2026-08-28, and the three obstacles above are closed

Each of the three was closed by measurement rather than argued away.
`HISTORY/powerpc.md` carries the detail; what follows is only which is which.

1. **Zstandard databases.** `scripts/resolve-anchor`, `scripts/gen-evidence` and
   `tests/static/40-mirrors-reachable.sh` each read a database in either
   compression and say what both reported when neither works. The same change
   also stopped them assuming the repository is named `core`, which ArchPOWER's
   is not.
2. **One host.** Not fixed. The floor for these three ports is one server rather
   than two, in the generator and in the reachability check, and the single
   point of failure is recorded rather than hidden. It is still TODO 6.
3. **Two repository sections.** `[base]` and `[base-any]`, each Including its
   own mirror list, because `base/any` is not `$repo/$arch` for any value of
   either. The evidence file joins against both, which is what proves the
   arrangement rather than merely accepting it.

⛔ One obstacle nobody had named turned up in its place: `docker/setup-qemu-action`
registers no big endian PowerPC emulator. `HISTORY/powerpc.md`.

## i686: blocked on an expired master key

Arch Linux 32 publishes a keyring as a package, which is the same shape as the
Arch Linux ARM case this repository already solves with a pinned fingerprint.
The keyring installs, every master key is trusted, and the transfers work. The
bootstrap still fails, on signatures.

| fact | value |
| --- | --- |
| keyring package | `archlinux32-keyring-20251214-1.0-any.pkg.tar.zst`, 38696 bytes |
| sha256 | `7600cd9ddabbbbb5643b0235646670d070a4848030fbe10c77939ea3aeee29a0` |
| trusted master keys | 5, listed in `archlinux32-trusted` |
| `pacman-key --populate archlinux archlinux32` | exit 0, all 5 master keys trusted |
| `base` package | `base-3-3.0`, resolving to 132 packages |
| `pacman` package | `pacman-7.1.0.r9.g54d9411-1.6` |
| mirrors probed | 14, of which 13 answered `core.db` with 200 |
| `core.db.sig` | 404 on every mirror, so the database is unsigned and `DatabaseOptional` applies |
| bootstrap result | `pacman` exit 1 after 365 seconds, 0 packages installed |

### The blocker, measured

One of the five master keys has expired:

```bash
gpg --homedir /etc/pacman.d/gnupg --with-colons --list-keys <fingerprint>
```

| master key | validity | expires |
| --- | --- | --- |
| `194E37A47A4C671807BACB37B1117BC1094EA6E9`, Erich Eckner | full | 2026-12-31 |
| `CE0BDE71A759A87F23F0F7D8B61DBCE10901C163`, Balló György | full | never |
| `A0B250C0FC9FC079EC04ADB7A50C0F20AEC3AF00`, Polichronucci | **expired** | **2026-01-16** |
| `D92CDDC155BCC8F550B5FCEC30AB721FE7400FCD`, Tyler Dence | full | never |
| `C426F2CED2D759ECEA1FA78A4BA3B2E330891150`, Andreas Baumann | full | 2026-11-27 |

`pacman-key` gives each master key ownertrust 4, which is marginal, and gpg's
default `marginals-needed` is 3. A packager key therefore reaches full validity
only when three master keys with current signatures have signed it.

The packager key `80EC18799E8BCD375C6E64ABE4D41569196B1160`,
`TasosSah (Arch32 Package Signing Key)`, carries exactly three master
signatures, and one of the three is the expired key:

```bash
gpg --homedir /etc/pacman.d/gnupg --list-sigs 80EC18799E8BCD375C6E64ABE4D41569196B1160
```

| signer | counts |
| --- | --- |
| `194E37A47A4C671807BACB37B1117BC1094EA6E9` | yes |
| `A0B250C0FC9FC079EC04ADB7A50C0F20AEC3AF00` | no, expired 2026-01-16 |
| `C426F2CED2D759ECEA1FA78A4BA3B2E330891150` | yes |

Two of three, where three are needed. The key sits at marginal validity and
`SigLevel = Required` rejects everything it signed.

⭐ **Causation is measured, not inferred.** Lowering `marginals-needed` from 3 to
2 against the same keyring moves the key from marginal to full:

```bash
gpg --homedir /etc/pacman.d/gnupg --check-trustdb
gpg --homedir /etc/pacman.d/gnupg --with-colons --list-keys 80EC18799E8BCD375C6E64ABE4D41569196B1160
# validity m
gpg --homedir /etc/pacman.d/gnupg --marginals-needed 2 --check-trustdb
gpg --homedir /etc/pacman.d/gnupg --marginals-needed 2 --with-colons --list-keys 80EC18799E8BCD375C6E64ABE4D41569196B1160
# validity f
```

⛔ That is a measurement of the cause. Lowering the threshold is not a fix and is
not shipped. Policy 5 keeps signature checking at full strength.

### What the failure looks like

Nine of the 132 packages in `base` are signed by that key and are refused:

```
error: ncurses: signature from "TasosSah (Arch32 Package Signing Key) <arch32@tasossah.com>" is marginal trust
:: File /var/cache/pacman/pkg/ncurses-6.4_20230520-3.0-i686.pkg.tar.zst is corrupted (invalid or corrupted package (PGP signature)).
error: failed to commit transaction (invalid or corrupted package)
```

The nine: `brotli`, `dbus-broker`, `dbus-broker-units`, `glib2`, `libcap-ng`,
`libffi`, `libseccomp`, `ncurses`, `popt`. `base` cannot be installed without
them, so the transaction commits nothing and the root stays empty.

⚠ **This corrects the earlier reading of this port.** Three previous attempts
failed on transfers and none reached a signature check, which was recorded as
"no trust blocker found". With the transfers working, the trust path is reached
and it does not pass. The keyring is not the problem; one signature short of the
threshold is.

### What would unblock it

Any one of these, and nothing less:

1. A newer `archlinux32-keyring` release carrying a renewed expiry on
   `A0B250C0FC9FC079EC04ADB7A50C0F20AEC3AF00`.
2. A newer `archlinux32-keyring` release in which
   `80EC18799E8BCD375C6E64ABE4D41569196B1160` carries a signature from a third
   master key whose own key is current.
3. The nine packages being rebuilt and signed by a key that already reaches full
   validity.

⚠ None of the three is available today. `20251214-1.0` is the newest keyring
both on the mirror and in the archive:

```bash
curl -s -L "https://mirror.archlinux32.org/i686/core/" | grep -oE 'archlinux32-keyring-[0-9][0-9a-zA-Z.-]*\.pkg\.tar\.[a-z]+' | sort -u
curl -s -L "https://archive.archlinux32.org/packages/a/archlinux32-keyring/" | grep -oE 'archlinux32-keyring-[0-9][0-9a-zA-Z.-]*\.pkg\.tar\.[a-z]+' | sort -u | tail -5
```

**Verdict: excluded, with the reason recorded.** Not because it was removed
before, and not because the port is inactive. It is excluded because a packager
key in the current keyring is one valid master signature short of the threshold
`SigLevel = Required` needs, and no keyring that fixes it is published.

⭐ **Re-check by re-running the bootstrap**, not by reading this page. The
scaffold is `.tmp/phasec/i686-bootstrap.sh` and it fails loudly at stage 5 while
this holds. A new keyring release is the event that changes the answer.
