# Actions only the maintainer can take

Five items, measured 2026-08-26. Item 1 is applied. The other four are proposed
with the reason and the exact command, and none of them has been applied.

## 1. Branch protection on `main`  ⭐ applied

Before, `main` was unprotected:

```bash
gh api repos/pkgforge-dev/docker-archlinux/branches/main/protection
```

```
Branch not protected (HTTP 404)
```

It is now:

| setting | value |
| --- | --- |
| required check | `Static suite and linters` |
| branch must be up to date | yes |
| approving reviews required | 1 |
| stale reviews dismissed | yes |
| enforced on admins | no |
| force pushes | denied |
| branch deletion | denied |
| conversations must resolve | yes |

⛔ **A pull request currently reaches the repository's credentials and packages
without any review.** The publish job holds `packages: write` and the Docker Hub
token, so a merged pull request can push to both registries.

Who can review, measured rather than assumed:

```bash
gh api repos/pkgforge-dev/docker-archlinux/collaborators \
  --jq '.[] | "\(.login) \(.role_name)"'
```

| login | role | can push |
| --- | --- | --- |
| `QaidVoid` | admin | yes |
| `Samueru-sama` | admin | yes |
| `Azathothas` | admin | yes |
| `psadi` | maintain | yes |

The other 16 collaborators are `read`. So a one reviewer rule draws from four
people, which is enough for it not to block the maintainer.

⭐ **What was applied**, requiring a passing check before merge and one review
from someone who already has push access:

```bash
gh api -X PUT repos/pkgforge-dev/docker-archlinux/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Static suite and linters"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false,
  "required_conversation_resolution": true
}
JSON
```

Why each field:

| field | reason |
| --- | --- |
| `required_status_checks.contexts: ["Static suite and linters"]` | the job in `.github/workflows/ci.yml`. ⛔ It had to be created first: the build workflow runs only on a schedule or a dispatch, so before it there was no pull request check at all, and requiring one that never runs leaves every pull request pending forever |
| `strict: true` | a branch behind `main` has to rebase, so the suite that passed is the suite for the merged tree |
| `enforce_admins: false` | ⚠ deliberate. With it on, an admin cannot merge a Dependabot pull request without a second admin, which is the opposite of very low maintenance |
| `required_approving_review_count: 1` | drawn from the four above |
| `dismiss_stale_reviews: true` | an approval is for the diff that was reviewed |
| `allow_force_pushes: false`, `allow_deletions: false` | `main` carries every published tag's source commit |
| `required_conversation_resolution: true` | a review comment cannot be merged past silently |

⚠ **What this does not do.** It does not stop an admin pushing to `main`
directly, by design. It does not require signed commits, because no contributor
here signs today and turning it on would block all four of them.

## 2. The GitGuardian secret

Secret scanning is GitGuardian, per the maintenance model. It needs a
`GITGUARDIAN_API_KEY` repository secret. The repository has two secrets today
and that is not one of them:

```bash
gh api repos/pkgforge-dev/docker-archlinux/actions/secrets --jq '.secrets[].name'
```

```
DOCKERHUB_TOKEN
DOCKERHUB_USERNAME
```

⛔ **Creating the secret is the maintainer's action.** Nothing in this
repository creates it, reads it, or works around its absence.

Once it exists, the scanning workflow can be added. It is not added first,
because a workflow that fails on every run for a missing secret trains people to
ignore a red mark.

## 3. The branches that are not `main`

⚠ **This section was rewritten after the history rewrite, which invalidated it.**
It said `debug` held no commit that was not already in `main`. `main` now has no
ancestry at all, so that is no longer the right comparison for anything.

```bash
git rev-list --count origin/main..origin/debug              # 2159
git rev-list --count origin/history-archive..origin/debug   # 0
git merge-base --is-ancestor origin/debug origin/history-archive && echo ancestor
```

⚠ **Re-measured 2026-08-29, and two of the three rows have moved.** Only
`main` and `history-archive` exist on the remote now.

```bash
gh api repos/pkgforge-dev/docker-archlinux/branches --jq '.[].name'
```

| branch | unique commits vs `history-archive` | state on the remote |
| --- | --- | --- |
| `history-archive` | it is the reference | present, ⛔ **not protected** |
| `debug` | 0, it is an ancestor of the archive | ⭐ deleted 2026-08-29 |
| `template-adoption` | **11** | ⛔ **gone, and not by this repository's doing** |

### ⛔ Protect `history-archive`

⭐ **The whole rewrite rests on this one ref.** `main` denies force pushes and
deletions; `history-archive` denies nothing, and `main` has no ancestry that
would keep those objects reachable if it went.

```bash
gh api -X PUT repos/pkgforge-dev/docker-archlinux/branches/history-archive/protection \
  --input - <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "lock_branch": true
}
JSON
```

⛔ Not applied. Changing branch protection is the owner's.

⚠ The commit `9d1e1429259625323139cb39dd1c81764c73501d` is written in `README.md`,
`HISTORY/rewrite.md` and the `main` commit body, so the branch can be recreated
from any clone that still has the objects. That is a name, not a copy.

### `debug`  ⭐ deleted

Tip `a809a2251aef65188c0390b8a36f566fd2279854`, 2025-11-14, a keepalive commit.

⛔ **Checked before deleting, not asserted.** Every commit on it was already
reachable from the archive:

```bash
git merge-base --is-ancestor origin/debug origin/history-archive && echo ancestor
git rev-list --count origin/history-archive..origin/debug   # 0
```

Deleted 2026-08-29 at the maintainer's direction, by
`gh api -X DELETE repos/pkgforge-dev/docker-archlinux/git/refs/heads/debug`.
Nothing was lost: the 2159 commits it named remain on `history-archive`.

### `template-adoption`  ⛔ gone from the remote

⛔ **This one held 11 commits that were on no other branch, and the remote no
longer has it.** A `git fetch --prune` on 2026-08-29 reported it deleted, along
with `freshness/mirrors-20260826`. ⚠ Neither was deleted by this session: the
only branch deleted here was `debug`, and the command is recorded above.

⚠ **The 11 commits survive in one place that is known**: the working clone on
the maintainer's workstation, where the local branch still points at
`8cf0ca698503ed09f153f1df2426b2414b4d4d1e`. They are the work between the
archive point and the rewrite:

```
8cf0ca6 record the fault that makes each test fail
0b0649e correct what a single architecture tag is, measured against a real run
14e4b18 run the static suite and both linters on every pull request
eccbcd2 remove the orphaned keepalive file, and record what the maintainer must apply
a35136a document what the image does, with examples that run
bf9e26d assert a reachable floor per mirror list, not every entry
fa1933f watch every pin, and record what was measured about the ports
6d4b92f split the build into resolve, a per architecture matrix, and a publish job
fdb90a9 add the static and image test suites, and the evidence generator
62592ca rebuild the bootstrap so it does not depend on its own output
2ee4af5 normalise line endings to LF in the repository
```

⛔ **The maintainer's call, and it does not keep.** Pushing a deleted branch back
is undoing somebody's decision, so it was not done. If those commits are wanted,
push the local ref back before that clone is garbage collected:

```bash
git push origin 8cf0ca698503ed09f153f1df2426b2414b4d4d1e:refs/heads/template-adoption
```

⚠ If they are not wanted, nothing needs doing and this entry can go. ⭐ What is
not acceptable is neither: an unreferenced commit in one clone is lost the day
that clone is cleaned, and nobody is told.

## 4. Actions creating pull requests

All three freshness workflows open pull requests with `gh pr create` and the
built-in token. The repository already allows it:

```bash
gh api repos/pkgforge-dev/docker-archlinux/actions/permissions/workflow
```

```json
{"default_workflow_permissions":"write","can_approve_pull_request_reviews":true}
```

⚠ **No change is needed, and one is worth considering.**
`default_workflow_permissions` is `write`, which grants every workflow write
access by default. Every workflow here declares `permissions: contents: read` at
the top and elevates per job, so the default does not apply to them. Setting the
default to `read` would make that explicit for anything added later:

```bash
gh api -X PUT repos/pkgforge-dev/docker-archlinux/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false
```

⛔ Verify the freshness jobs still open pull requests after changing it. The
per-job `pull-requests: write` should be enough, and that is untested.

### ⛔ A freshness pull request carries no status check

Measured on 2026-08-26, the first time these workflows were fired. Run
`33001891317` opened pull request 2. Its CI run was created and then held:

```bash
gh run list --branch freshness/mirrors-20260826 --json databaseId,event,status,conclusion
```

```
33002123968  pull_request  completed  action_required
```

```bash
gh pr checks 2
```

```
no checks reported on the 'freshness/mirrors-20260826' branch
```

⚠ **A pull request opened with the built-in `GITHUB_TOKEN` does not start its
own checks.** The run exists and waits for a human to approve it, so the
required check `Static suite and linters` never reports and branch protection
cannot be satisfied on its own.

⛔ **The consequence is the opposite of very low maintenance.** Merging a
freshness pull request takes two deliberate actions rather than one: approve the
held run, then merge. Pull request 2 was merged with `--admin` for exactly this
reason.

⭐ **The fix needs a credential, so it is the maintainer's.** Opening these pull
requests with a personal access token or a GitHub App installation token instead
of `GITHUB_TOKEN` makes their checks start normally. ⛔ Creating that secret is
not the agent's action. Ask, do not create.

⚠ **What is not verified.** Whether a token would also need `workflow` scope
here, and whether the organisation applies a policy of its own. The
organisation-level endpoint refuses this account:

```bash
gh api orgs/pkgforge-dev/actions/permissions/workflow
```

```
You must be an org admin or have the actions policies fine-grained permission. (HTTP 403)
```

⭐ Until it is fixed, each freshness pull request body says so and names the run
that did test the tree, so a reviewer is not left wondering where the check is.

## 5. Dependabot preserving hash pins

`.github/dependabot.yml` covers `github-actions` and `docker`. Whether
Dependabot updates a commit-hash pin to a new hash, rather than rewriting it
back to a tag, is **not verified here**. It cannot be: Dependabot runs
server-side and only on a branch it has been enabled for.

⭐ **The risk is guarded rather than assumed.** Three tests fail on a pin that
has become a tag, so such a change fails CI on the bot's own pull request:

| test | fails on |
| --- | --- |
| `tests/static/00-workflow-branch-buildable.sh` | `actions/checkout` at a tag |
| `tests/static/50-supply-chain.sh` | any action at a tag, and any pinned action with no version comment |
| `tests/static/10-bootstrap-not-circular.sh` | a `FROM` that is not `@sha256:` |

Seen to fail, against a tree with `actions/checkout@v7.0.1` and
`docker.io/library/archlinux:latest` substituted in:

```
not ok 1 - actions/checkout is pinned to a commit hash
not ok 1 - action is pinned to a commit hash at .github/workflows/build-deploy.yml:59
not ok 1 - every base image is pinned by digest
```

⚠ If Dependabot does rewrite pins to tags, its pull requests will be red and
that dependency belongs to a freshness job of its own instead.

## 6. Forks and the fork relationship  ⭐ done

⚠ **This was an open maintainer action and it is closed.** The repository was a
fork of `fwcd/docker-archlinux` in GitHub's data model, and the maintainer was
contacting fork owners so it could be detached.

Measured 2026-08-29:

```bash
gh api repos/pkgforge-dev/docker-archlinux --jq '{fork:.fork, parent:(.parent.full_name // "none"), forks:.forks_count}'
```

```json
{"fork":false,"forks":0,"parent":"none"}
```

⭐ Detached, with no parent and no forks of its own. ⛔ Nothing in the repository
changed for it, which is what was written down at the time and is still true.
The repository was already documented as independent.
