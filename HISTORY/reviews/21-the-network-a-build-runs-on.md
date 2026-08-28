# Review 21: the network a build runs on

**Lens.** Everything this repository fetches, it fetches from somewhere, and
"somewhere" answered differently on a workstation and on a GitHub runner three
times in one session. This review asks which of this repository's fetches have
ever been exercised from more than one network, what each does when the answer
differs, and where a reader would look when one starts refusing.

**Date.** 2026-08-28, against the working tree of the commit this ships in, at
`57a3bef` amended.

⚠ Distinct from review 9, an operator during a mirror outage, which asked what
happens when a mirror is **down**. This asks what happens when it is up and
refuses **you**. A down mirror fails the same way for everyone; this one passes
locally and fails in CI, which is the shape that reaches `main`.

---

## What was opened

- `scripts/resolve-anchor`, whole, 144 lines.
- `scripts/gen-mirrorlist`, whole, 430 lines.
- `scripts/check-keyring-pin`, the mirror handling, lines 91 to 230 of 395.
- `scripts/check-image-pins`, the fetch, lines 1 to 60.
- `scripts/gen-evidence`, `db_sources` and `read_desc`, lines 160 to 265.
- `scripts/check-anchor-floor`, whole.
- `scripts/build-pacman-static`, `fetch`, lines 138 to 166.
- `bootstrap/any/usr/local/bin/install-port-keyring`, whole, 331 lines.
- `tests/static/40-mirrors-reachable.sh`, whole, 240 lines.
- `tests/static/65-fetch-policy.sh`, whole.
- Runs `33194668740`, `33194671836`, `33194179114` and `33195922986`.

## What was compared

Every fetch in `scripts/`, `bootstrap/any` and the workflows, against three
questions: does it try more than one source, does it say which source answered,
and does it say what each refusal was.

| fetch | more than one source | names the source that answered | names each refusal |
| --- | --- | --- | --- |
| `resolve-anchor` | yes, the mirrorlist | no | yes |
| `gen-mirrorlist` anchors | yes | yes, by count | yes |
| `gen-evidence` | yes, the list the section Includes | yes | yes |
| `install-port-keyring` | yes, since this change | yes | yes |
| `check-keyring-pin` | yes, since this change | yes, since this change | yes |
| `check-anchor-floor` | no, GHCR only | not applicable | yes |
| `check-image-pins` | no, the registry the pin names | not applicable | yes |
| `build-pacman-static` | ⛔ **no, and deliberately** | not applicable | yes |

## What was found

### 1. ⭐ Three fetches read one source and stopped, and each failed in a different step

`install-port-keyring` and `check-keyring-pin` both read a single `mirror`
field. `resolve-anchor` already walked the whole mirrorlist. The consequence was
not one failure but three, staged:

- `resolve-anchor` failed first, in `Resolve inputs`, so nothing built. Run
  `33193952569`.
- With the mirrorlist fixed, `install-port-keyring` failed, in the first
  `Dockerfile` step that touches the network. Run `33194671836`, `ppc64le`.
- `check-keyring-pin` would have failed weekly, in `freshness-keyring.yml`,
  which nobody was running.

⭐ **The third is the one worth the review.** The first two failed loudly the
first time they ran. The third would have failed on a schedule, in a job whose
failing is described as a normal result, and the reason would have read as
"upstream moved" rather than "this runner cannot reach that host".

### 2. ⭐ The probe was not asking the question the tools ask

`tests/static/40-mirrors-reachable.sh` sent curl's default user agent.
`gen-mirrorlist` and `resolve-anchor` send
`docker-archlinux-mirrorlist/1`. A mirror filtering on identity would answer one
and refuse the other, and the test's verdict would have been about a request
this repository never makes. Fixed here.

⚠ It did not change the answer in this case, and that is itself a finding: the
403 is the same for every identity tried, which is what said the block was the
source network. A test that had already sent the right identity would have
narrowed it one round trip sooner.

### 3. ⚠ Two fetches read one source by design, and only one says so

`check-anchor-floor` reads GHCR's tag list and `check-image-pins` reads the
registry each pin names. Neither can fall through, because for both of them the
source **is** the fact: another registry's tag list is not this repository's
floor. Both say so in their own headers.

⛔ `build-pacman-static` also refuses to fall through, and that one is a
security property rather than a limitation: a checksum mismatch stops the build
and no substitute is fetched. Its comment says so in the imperative. That is the
correct shape and this review confirms it rather than finding it.

### 4. ⚠ A new dependency arrived without a watcher

`api.rv.pkgforge.dev` is now in three mirror lists, three anchor files and one
keyring pin. Nothing in this repository checks it, and no freshness job names
it. If it stops answering, the failure appears as three architectures failing in
`Resolve inputs`, which reads as ArchPOWER being down.

⚠ **Not fixed here, and recorded.** `HISTORY/powerpc.md` says it plainly under
what is not proven. Writing a watcher for it belongs with TODO 6, which is about
exactly this class.

### 5. ⭐ The one place the fall through order carries meaning

Every PowerPC list has the origin first and the proxy second. That ordering is
what keeps the proxy carrying only what cannot reach the origin, and it is a
property of the generated file rather than of any code: `gen-mirrorlist` writes
anchors in the order the anchors file lists them, unranked.

⚠ **Nothing asserts the order.** A future regeneration that sorted the anchors
would silently route every consumer through the proxy, and every test would
still pass. This is a real gap and it is not closed here: the assertion would
have to know which of two servers is the origin, and nothing in the file says.

## ⚠ What this did not look at

- ⛔ **Whether the proxy is trustworthy.** It is operated by the same
  organisation as this repository. The review took the signature chain as the
  answer to what it could do, and did not audit the service.
- **The registries.** GHCR and Docker Hub are fetched by several scripts and by
  every consumer. Neither was probed from more than one network here.
- **The plain http ARM mirrors.** 20 of the shipped mirrors are `http`, and this
  review did not re-examine that; `HISTORY/arm-rollback.md` has it.
- **Rate limits.** Every measurement here was a single request. A mirror that
  answers one probe and refuses fifty would look healthy in all of them.
- **DNS.** Every failure seen was an HTTP status. A host that resolves
  differently from two networks would not have been distinguished.

## Change summary

Files touched by the change this reviews: 57 changed, 4186 insertions, 88
deletions against `dcf9263`. The parts this review covers: `install-port-keyring`
42 lines changed, `check-keyring-pin` 37, `tests/static/40-mirrors-reachable.sh`
61, and nine new files under `mirrors/` totalling 150. This review adds no change
of its own.
