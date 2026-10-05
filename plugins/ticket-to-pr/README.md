# ticket-to-pr

Take a Jira ticket to a pull request in one manual command.

The pipeline is **ticket to In Progress → implement → pre-review → commit →
push → PR → ticket to Code Review → summon reviewers → wait for and handle
their reviews**. Implementation is the
only mandatory step and is done by the current session; the rest is enabled by a per-team profile and, in partial
mode, picked from a checklist. Open questions found in the ticket and the
code are asked in one round before any work starts, in both modes. Pre-review comes before the commit so that
fixes land in the same commit and history shows the result, not the process.

## Commands

| Command | What it does |
| --- | --- |
| `/ticket-to-pr:full <ticket>` | Every step the profile enables, no process questions |
| `/ticket-to-pr:partial <ticket>` | Checklist of the profile's steps, then no questions |
| `/ticket-to-pr:setup [name]` | Create or update a profile and map the current repo to it |

`<ticket>` is a `https://<site>.atlassian.net/browse/KEY-123` link or a bare
key. An unmapped repository runs setup first, then continues.

## Profile

Everything team-specific lives in `profiles/<name>.md` under the plugin's data
directory (`~/.claude/plugins/data/ticket-to-pr-<marketplace>/`), picked by
the repo's git remote via `config.md`. Sections: `Jira` (site, cloudId),
`Ветка` (base, naming), `Проверка` (test/lint commands), `Pre-review`
(Claude subagent with a model id, Codex, or both), `Коммит` (message format),
`PR` (a PR-creating skill named in the profile, or `gh pr create` rules),
`Ревьюеры` (name → summon command → where the reply lands and how long to wait
for it: Copilot via the reviewers API, Claude via an `@claude` comment),
`Статусы` (the ticket's path through the workflow and
the statuses to reach before work and after the PR). A missing optional
section removes the step. Profiles are plain markdown, so a team creates its own by running setup once.

## Pre-review

Selected reviewers run in parallel on the whole branch diff plus uncommitted
changes, with the ticket and the author's assumptions as context, in
adversarial mode. Each finding is verified against the code; confirmed ones
are fixed and the reviewers run once more. What remains goes into the PR body
and the final report. An unavailable reviewer is skipped and reported, never
silently replaced by self-review.

## PR reviews

A summoned reviewer is a promise to handle its review. The skill waits for
each reply where the profile says it lands, up to the profile's deadline: with
an event-driven PR watcher when the host has one (T3 Code's
`watch_pull_request`), otherwise a `Monitor` loop over the PR's reviews. Each
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

`gh` (authenticated), the Atlassian MCP server; `codex` only if the profile
lists it. Other plugins' PreToolUse gates on PR creation are respected: the skill
follows their instructions and retries.
