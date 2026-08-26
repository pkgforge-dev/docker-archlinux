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

| branch | unique commits vs `history-archive` | protected |
| --- | --- | --- |
| `history-archive` | it is the reference | ⛔ **no** |
| `debug` | 0, it is an ancestor of the archive | no |
| `template-adoption` | **11** | no |

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

### `debug`

Tip `a809a22`, 2025-11-14, a keepalive commit. It holds nothing the archive does
not.

```bash
git push origin --delete debug
```

⛔ Proposed, not done.

### `template-adoption`

⚠ **Deleting this one loses commits.** It holds 11 that are on no other branch,
the work between the archive point and the rewrite:

```bash
git log --oneline origin/history-archive..origin/template-adoption
```

⛔ Proposed for nothing. Either keep it, or move its tip into the archive first.
Deleting the last reference to a commit is not an action to take on somebody
else's behalf.

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
