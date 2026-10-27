# ticket-to-pr

Take a Jira ticket to a pull request in one manual command.

The pipeline is **acceptance criteria → ticket to In Progress → implement →
automated checks → verification against the criteria → pre-review → commit →
push → PR → ticket to Code Review → summon reviewers → wait for and handle
their reviews**. Criteria, implementation and the automated checks are
mandatory and done by the current session; the rest is enabled by a per-team profile and, in partial
mode, picked from a checklist. Open questions found in the ticket and the
code are asked in one round before any work starts, in both modes. Pre-review comes before the commit so that
fixes land in the same commit and history shows the result, not the process.

Every ticket is worked in its own git worktree of the ticket branch, created
from a fresh base wherever the agent's own rules put worktrees (CLAUDE.md,
memory; otherwise `<main checkout>/.claude/worktrees/<branch>`) and entered with
`EnterWorktree`, so hooks that read the session's cwd see the ticket branch.
The main checkout is never switched; an existing worktree or local branch of
the ticket is reused. `/ticket-to-pr:done` removes the worktree after merge.

## Commands

| Command | What it does |
| --- | --- |
| `/ticket-to-pr:full <ticket>` | Every step the profile enables, no process questions |
| `/ticket-to-pr:partial <ticket>` | Checklist of the profile's steps, then no questions |
| `/ticket-to-pr:deploy <ticket> <contours>` | Roll the ticket branch out to the named contours through a checklist, health-check, report |
| `/ticket-to-pr:done <ticket or PR>` | Merge the ticket's PR if it is green, move the ticket to its final status, remove the branch's worktree and local branch |
| `/ticket-to-pr:setup [name]` | Create or update a profile and map the current repo to it |
| `/ticket-to-pr:journal` | Review the skill's journal: run summary, grouped open events, fixes to the skill, profile and profile scripts as the user picks |

`<ticket>` is a `https://<site>.atlassian.net/browse/KEY-123` link or a bare
key. An unmapped repository runs setup first, then continues.

## Deploy

`/ticket-to-pr:deploy` rolls the ticket branch out before the merge, to
exactly the contours named in the command — it never picks one itself and is
never inferred from a plain-language request. It walks a 15-item checklist
and reports on every item: the PR and the services listed in its deploy
section, contours allowed by the manifests' `allowed-datacenters`, the PR's
pre-deploy steps confirmed, master merged into the branch, CI green on HEAD
(external Jenkins checks included), a branch build made from HEAD that
contains every service, nobody else deploying the service right now, the
user's own lock in the team's lock bot and no one else's, and what each
contour runs now (the rollback parameters). Then the deploy job runs, each judged by its status
(SUCCESS and UNSTABLE both pass — the job marks UNSTABLE only for a failed
deploy-referee call) and by the image tag of every workload in the cluster,
and a health check right after and again
5 minutes later: rollout status, pods Ready, image tag, restarts / CrashLoop /
OOMKilled, old ReplicaSet scaled down, error logs before vs after, consumer lag
for workers and 5xx share for HTTP services. CPU, memory and latency are not
checked: the deploy-referee judges them against absolute thresholds rather
than the pre-deploy level, so its verdicts are left to its channel. Only services (Deployments) on prod contours are health-checked: a dev-only deploy and CronJob tasks on any contour report the rollout
result alone, and each service gets the named contours its manifests allow (the PR's deploy block is only cross-checked), and the rollout is a plan of rectangular runs — one run per distinct set of contours, dev counted like any prod contour, all runs in parallel with no "dev first" gate — so no service is ever sent to a contour it isn't allowed in (the deployer may fail on it even when the manifest's whitelist would skip it); the prod health check is taken once all runs with prod contours finish.
Master is merged into the branch only when its new commits touch the deployed
services or the packages they import. A one-line status is posted at every
phase (preparing, deploying, each finished contour, health check).
Any ❌ stops the run with a report — it never rolls back, restarts, takes a
lock or resolves a merge conflict on its own. The ticket moves to the
profile's `При деплое:` status at the start: running the command is the
decision that it is ready to deploy. The last item checks the ticket's
criteria that are observable only after rollout (logs, metrics on the deployed
contours) and records each result, or "too early", in the criteria file.

## Done

`/ticket-to-pr:done` is separate from the pipeline: it is run when the PR has
been reviewed (and rolled out, if the team deploys branches before merging).
Invoking it is the permission to merge, so it asks nothing — but it merges
only a green PR: open, not a draft, no conflicts, `mergeStateStatus: CLEAN`,
every check finished as success/skipped/neutral, no changes requested, no
unresolved review threads. Anything else stops with the failed conditions
listed; `--admin` and `--auto` are never used. The merge uses the profile's
method (`gh pr merge --squash`) pinned with `--match-head-commit` to the
commit that was checked, so a push in between makes GitHub refuse. Only after
the PR reads `MERGED` is the ticket moved along the path to the profile's
`Финиш:` status — and only when no follow-up is left open: the ticket's
"После мержа" items (a prod toggle, a config, docs, a reply someone is
waiting for) and post-rollout criteria the deploy has not confirmed. Done asks
which of them are already done, since a session cannot see a reply or a prod
toggle; anything still open keeps the ticket in its current status, is listed
in the report and, on the merging run, posted as a ticket comment. Running
done again on the merged PR skips the merge and re-checks the follow-ups.

Then done cleans up after the ticket: the worktree the PR branch is checked
out in is removed with `git worktree remove` and the local branch with
`git branch -D` (squash never makes it an ancestor of the base). It removes a
worktree only when `git status --porcelain` is empty and its `HEAD` is the
merged `headRefOid` — never with `--force`, never the main checkout, and it
leaves the worktree first if the session runs inside it. Anything left behind
is listed in the report; a failed cleanup does not undo the merge.

Last, done counts the open events in the journal (`Статус: открыто`) and, if
there are any, names the count after the report and suggests
`/ticket-to-pr:journal` — it never runs the review itself.

## Journal

Every command appends to `journal.md` in the plugin's data directory: an
event the moment something goes wrong in the skill itself — an instruction
that no longer matches reality, a retried call or workaround, a failing
profile script, an empty answer that nearly led to a false conclusion, a
process correction by the user — and one summary line per run (command,
ticket, result, duration, tool calls, events). A ❌ that honestly reports the
outside world (red CI, someone else's lock) is not an event.
`/ticket-to-pr:journal` summarizes the runs, groups open events by where the
fix belongs, proposes one concrete edit per group and applies only what the
user picks: profile and scripts in the data directory, the skill in the
plugin's source repository with a version bump (never in the plugin cache),
committed and pushed only with consent. Closed events move to
`journal-archive.md`.

## Profile

Everything team-specific lives in `profiles/<name>.md` under the plugin's data
directory (`~/.claude/plugins/data/ticket-to-pr-<marketplace>/`), picked by
the repo's git remote via `config.md`. Sections: `Jira` (site, cloudId),
`Ветка` (base, naming), `Проверка` (test/lint commands), `Верификация`
(the verifier's model and reasoning effort), `Pre-review`
(one line per reviewer: model and reasoning effort), `Коммит` (message format),
`PR` (a PR-creating skill named in the profile, or `gh pr create` rules),
`Ревьюеры` (name → summon command → where the reply lands and how long to wait
for it: Copilot via the reviewers API, Claude via an `@claude` comment),
`Мерж` (the `gh pr merge` method for done), `Деплой` (build and deploy jobs,
contours with their kubectl context, lock-bot message, logs and metrics,
wait deadlines),
`Статусы` (the ticket's path through the workflow and
the statuses to reach before work, after the PR and after the merge). A missing optional
section removes the step. Profiles are plain markdown, so a team creates its own by running setup once.

## Verification

Right after the question round and before any code, the ticket's `DOD:`,
`Definition of Done` and `Тесты` items are copied verbatim into
`~/.cache/<ticket>/acceptance.md`, each bound to how it will be proven: a test,
a command, or an observation after rollout. Deciding what counts as done is
the ticket author's job; the skill only binds each item to a check, and asks
only when the ticket has no `DOD:`, the `DOD:` is preliminary, or an item
cannot be checked. The file changes later only through a question to the
user, and the ticket is updated with it.

Tests for the criteria are written before the fix. The automated checks run
the profile's commands, prove every new test fails with the production
changes stashed, and list test-weakening signals (deleted cases, added skips,
changed expectations). Then an independent Claude subagent — fresh context,
no author session — reruns the evidence itself and reports per criterion
(met / not met / after rollout / unverifiable), diff hunks that serve no
criterion or fall out of scope, and whether each test change is legitimate.
Up to two fix rounds; a criterion still unmet stops the pipeline before the
commit. Fixes from pre-review and PR reviews rerun the automated checks and,
when they touch the evidence, the verifier.

## Pre-review

Selected reviewers run in parallel on the whole branch diff plus uncommitted
changes, with the ticket and the author's assumptions as context, in
adversarial mode. Each finding is verified against the code; confirmed ones
are fixed and the reviewers run once more. What remains goes into the final
report, not the PR body: the body describes the change, not the work on it, and
is written by the PR creator alone. An unavailable reviewer is skipped and reported, never
silently replaced by self-review.

The profile names each reviewer by model and reasoning effort (`opus`,
`sol` — the latest of the family — or an exact id), never by launch command: the session picks the mechanism its
environment offers — the built-in subagent tool for its own provider's models,
an orchestrator that runs other providers' agents, or the provider's CLI —
as long as it gives a fresh context, the same working tree, the full result
and a completion signal. The same profile therefore works in a terminal and
in a host with task delegation. Known pitfalls of the Codex CLI are kept as
notes, not as the prescribed route.

## PR reviews

A summoned reviewer is a promise to handle its review. The skill waits for
each reply where the profile says it lands, up to the profile's deadline, with
a `Monitor` loop over the PR's reviews — no host-specific PR watchers, so it
behaves the same in any Claude Code environment. Each
comment is verified against the code like a pre-review finding; confirmed ones
are fixed in a new commit pushed on top (never a force-push — reviewers have
already seen the history), and every thread gets a reply naming the outcome.
A reviewer silent past its deadline is reported, not waited on forever.

## Jira statuses

The ticket is moved forward one transition at a time along the profile's
path, each transition found by the status it leads to. A ticket already at or
past the target is left alone, as is one outside the path (Inbox, Done): the
pipeline never moves a ticket backwards or guesses a route. A failed transition
is reported and does not stop the pipeline.

## Requirements

`gh` (authenticated), the Atlassian MCP server; for a reviewer on another
provider's model, a way to run it in the session's environment (an
orchestrator or the provider's CLI, such as `codex`). Other plugins' PreToolUse gates on PR creation are respected: the skill
follows their instructions and retries.
