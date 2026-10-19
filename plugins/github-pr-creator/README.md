# github-pr-creator

Create a pull request from the current branch with a body a reviewer can act
on: what the change does, in plain words, and how to roll it out and back.

The skill fills exactly three things: the title, the body and the base branch.
Labels, reviewers, draft state, assignee, milestone and projects are left alone
on purpose — they are decisions about the team's process, and a wrongly
requested reviewer is noise for a real person. It pushes the branch when the
branch is not on the remote yet, and it never commits, merges or rebases.

## What the body says

The ticket answers "why", so the body links to it instead of retelling it. Past
the link, the body carries three things and nothing else:

- **Description** — prose for a teammate who knows the system but not the
  session: what the change does and, in broad strokes, how — so they read it,
  understand what changes, and go to the code for the details. It tells, it
  does not steer: no "the key place to review", no "worth checking".
  Written from the diff, in domain words; identifiers only where they help find
  the place in the diff. No per-file retelling, no retelling of the ticket, no
  work history (test runs, review rounds, discarded options), and no extra
  sections — "verified", "decisions", "review notes" are not added even when a
  calling skill asks for them; whatever of that a reviewer needs becomes a
  sentence in the description.
- **Rollout** (`## Деплой`) — mandatory, three blocks in time order, each a
  bold label over a numbered list, an empty block spelled out as "Нет.":
  - *before rollout* — secrets (name and vault path, never a value), config
    keys, topics and queues that must exist first, hand-run migrations, PRs in
    other repositories;
  - *rollout* — one item per service in deploy order: service → its production
    clusters, then why it sits at that position. Only services that must be
    rolled out for the change to take effect are listed; a service that merely
    recompiles a shared package and behaves the same is not an item, and when
    nothing needs rolling out the block says so ("Не требуется:" plus the
    reason). Clusters are read from the service's deploy manifest in the
    repository at PR time, never from memory; the dev contour is omitted
    because nearly every service has one, and only the deviations are marked
    ("без dev", "не деплоится");
  - *after rollout* — flags to enable, consumers to catch up, keys to remove.
- **Rollback** (`## Откат`) — mandatory, a numbered list of what to do if
  something breaks after the rollout, written for the on-call engineer in the
  middle of an incident: the kill switch first (a flag or config key) when the
  change has one, then the previous version of the rolled-out services (with
  the order only when it matters), and an explicit list of what a rollout does
  not undo — migrations without a down file, data or events the new code
  already wrote and whether the old version reads them, config keys removed
  after rollout. Every compatibility claim is checked in the code at PR time
  or asked before creation; a trivial rollback is one item plus the checked
  fact ("no migrations, flags or new-format data").

The body ends with the attribution footer `🤖 Generated with <tool> (<model>)`.

When the repository ships a PR template, the skill follows it strictly: its
sections, its order, no sections added (the rollout and rollback sections included), the
HTML comments with author hints stripped, the ticket link placed in whichever
section is about context. The body language is Russian; an English template
makes the body English.

## What the title says

`<type>(<scope>): <KEY-123> <summary>` — the type from the
[Angular commit guidelines](https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md),
the scope a service or domain, the summary imperative, lowercase, no trailing
period. A title format stated in the repository's `README.md` or
`CONTRIBUTING.md` wins, because the PR title becomes the squash-commit
subject the repository's automation reads.

## Facts first

Every fact in the body is verified in its primary source before it is written:
services named in the session are checked against the diff, clusters come from
the deploy manifests, new config keys and secrets are found in the diff and
confirmed by grep, the ticket key comes from the branch name. Whatever stays
unknown is asked in a single round before `gh pr create` — the created PR never
carries a placeholder or an open question, because a PR is a claim that the
work is ready for review.

Secret values never reach the body, whatever their source.

## Requirements

- The [`gh` CLI](https://cli.github.com/), authenticated.
- A Jira site URL for the repository — asked once on first use and kept in
  `config.md` under the plugin's data directory (`${CLAUDE_PLUGIN_DATA}`,
  normally `~/.claude/plugins/data/github-pr-creator-<marketplace>/`). That
  table is the plugin's only setting; everything else is read from the
  repository and the session.

## Usage

Trigger phrases like:

- "создай PR", "запили пулик", "оформи ПР на это"
- "open a PR", "create a pull request for this branch"
- "перепиши описание PR" — rewrites the body of an existing PR after reading
  it and showing the new version first

After creating the PR the skill replies with the link and nothing else.

Skills: `github-pr-creator`.
