# Review 9: an operator during a mirror outage

**Lens.** A mirror is down, slow, or serving the wrong thing, and somebody is
reading the failure at 3am. Does the run fail, does it fail in the right place,
and does the message say which server to stop trusting.

**Date.** 2026-08-27. Unlocked by section 2 of the brief being decided; it could
not be written before there was a transfer policy to review.

---

## What was checked

Every path a bad mirror can take through this repository, run rather than read.

⭐ **A total outage fails loudly, in the right place, naming every server.**
Three unreachable mirrors for one architecture:

```
resolve-anchor: cannot fetch file:///nowhere/one/core.db: curl: (37) ...
resolve-anchor: cannot fetch file:///nowhere/two/core.db: curl: (37) ...
resolve-anchor: cannot fetch file:///nowhere/three/core.db: curl: (37) ...
resolve-anchor: could not resolve the pacman version for down from any server
  every server in that list was tried and none served a readable core database
  probe them with: bash tests/run.sh static
  regenerate the list with: scripts/gen-mirrorlist down
```

Exit 1, in the resolve job, before anything is built or pushed. Every server is
named, and there are two next steps rather than none.

⭐ **A partial outage does not become a release.** Five mirrors serving five
different kinds of wrong, and the sixth serving the truth: all five are refused
by name and the sixth answers.
`tests/static/67-mangled-responses.sh` is that, as a test.

⭐ **Nothing can hang.** `tests/static/65-fetch-policy.sh` asserts all 14 fetches
in `scripts/`, the workflows and `bootstrap/any` set `--connect-timeout` and
`--max-time`. curl's default connect timeout is around two minutes and it has
no default total timeout, so the previous behaviour on a mirror that connects
and then stalls was to hold the job until CI killed it, six hours later.

---

## What this review changed

⛔ **A guard that a transient could switch off.** `scripts/check-anchor-floor`,
added earlier the same day, read the tag list and treated an empty one as "this
repository has published nothing yet, so there is no floor" and passed. An
intermediary answering 200 with an error object produces exactly that shape.
The rollback guard would have been off, silently, on precisely the kind of day
this review is about.

⭐ It now requires the response to name its own repository before any tag in it
is trusted, and refuses with the first lines of what did arrive when it does
not. An empty tag list from a body that **is** a tag list is still the first
publish for a new repository, and still passes.

⚠ **Two diagnostics were found empty or misleading and fixed earlier the same
day**, both in this lens's territory and both recorded in the commit:
`resolve-anchor` printed tar's blank first line as the reason a database was
unreadable, and two scripts fetched without `-f`, so a mirror answering 403 was
reported as a corrupt archive.

---

## What was found and not changed

⚠ **An outage of the registry now blocks the publish earlier than it used to.**
`check-anchor-floor` needs the tag list, so GHCR being unreachable fails the
resolve job. This is not a new single point: the build pushes to GHCR anyway, so
that run was going to fail regardless. It fails sooner and with a clearer
message. Recorded rather than worked around.

⚠ **There is still no fallback for every mirror of one architecture being
down.** The build fails, which is correct and total. Section 2 of the brief
carries the option and the argument against it: a stale image that says so in a
label nobody reads may be worse for a consumer pulling `:latest` than a build
that failed and left yesterday's image in place.

⚠ **`riscv64` has no mirror generator.** `mirrors/riscv64.pool` is six hand
maintained servers. That is section 3 of the brief, not this review.

---

## What this review did NOT look at

- **The registries themselves.** Whether GHCR or Docker Hub throttle or fail
  mid-copy is not covered here. `HISTORY/tests-seen-to-fail.md` records that a
  copy interrupted partway has never been produced deliberately.
- **pacman's own transfer behaviour during the build.** The timeouts asserted
  here are curl's, in this repository's scripts. What pacman does with a slow
  mirror inside the Dockerfile is upstream's, and `XferCommand` is deliberately
  not set: it ships in the consumer's `pacman.conf` and policy 7 governs that.
- **A mirror that is fast, reachable and lying.** That is the rollback lens, and
  it is [`../arm-rollback.md`](../arm-rollback.md), not this.
- **DNS.** Every failure mode here was produced with local files. A resolver
  that answers wrongly rather than not at all was not tested.

## Change summary

| file | added | removed |
| --- | --- | --- |
| `scripts/check-anchor-floor` | 14 | 3 |
| `HISTORY/reviews/9-an-operator-during-a-mirror-outage.md` | new | - |
