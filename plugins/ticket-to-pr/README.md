# ticket-to-pr

Take a Jira ticket to a pull request in one manual command.

The pipeline is **implement → pre-review → commit → push → PR → summon
reviewers**. Implementation is the only mandatory step and is done by the
current session; the rest is enabled by a per-team profile and, in partial
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
`Ревьюеры` (name → summon command: Copilot via the reviewers API, Claude via
an `@claude` comment). A missing optional section removes the step. Profiles
are plain markdown, so a team creates its own by running setup once.

## Pre-review

Selected reviewers run in parallel on the whole branch diff plus uncommitted
changes, with the ticket and the author's assumptions as context, in
adversarial mode. Each finding is verified against the code; confirmed ones
are fixed and the reviewers run once more. What remains goes into the PR body
and the final report. An unavailable reviewer is skipped and reported, never
silently replaced by self-review.

## Requirements

`gh` (authenticated), the Atlassian MCP server; `codex` only if the profile
lists it. Other plugins' PreToolUse gates on PR creation are respected: the skill
follows their instructions and retries.
