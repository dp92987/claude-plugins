# github-pr-creator

Create a pull request from the current branch with a body a reviewer can act
on: what was done, and how to roll it out.

The skill fills exactly three things: the title, the body and the base branch.
Labels, reviewers, draft state, assignee, milestone and projects are left alone
on purpose — they are decisions about the team's process, and a wrongly
requested reviewer is noise for a real person. It pushes the branch when the
branch is not on the remote yet, and it never commits, merges or rebases.

## What the body says

The ticket answers "why", so the body links to it instead of retelling it. Past
the link, the body carries three things:

- **What was done** — one or two paragraphs written from the diff, naming the
  service, file, table, topic or flag exactly. Not a per-file retelling of the
  diff and not a retelling of the ticket.
- **Verified** — one line with what actually ran in the session and its result,
  or an explicit "not verified". An omitted line reads as "verified but not
  written down"; an explicit one reads as a fact.
- **Rollout** (`## Выкатка`) — mandatory, three blocks in time order, each a
  bold label over a numbered list, an empty block spelled out as "Нет.":
  - *before rollout* — secrets (name and vault path, never a value), config
    keys, topics and queues that must exist first, hand-run migrations, PRs in
    other repositories;
  - *rollout* — one item per service in deploy order: service → its production
    clusters, then why it sits at that position. Clusters are read from the
    service's deploy manifest in the repository at PR time, never from memory;
    the dev contour is omitted because nearly every service has one, and only
    the deviations are marked ("без dev", "не деплоится");
  - *after rollout* — flags to enable, consumers to catch up, keys to remove.

The body ends with the attribution footer `🤖 Generated with <tool> (<model>)`.

When the repository ships a PR template, the skill follows it strictly: its
sections, its order, no sections added (the rollout section included), the
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
