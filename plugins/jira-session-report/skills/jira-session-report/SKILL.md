---
name: jira-session-report
description: >-
  Post a "Claude Code session report" comment on a Jira ticket — a full report of
  what the session accomplished (task summary, PRs, review outcomes, deploy notes)
  with the session metadata folded in: session link, total cost, API + wall
  duration, code changes, and per-model token usage read from `/usage`. Use
  whenever the user wants to record/log a session on a Jira issue: "add session
  info to PROJ-1234", "post the session report to the ticket", "log this session on
  jira", "add the usage/cost to the ticket", "report this session", or when
  wrapping up a ticket / moving it to Done. Trigger even if they don't say the
  word "report" — any request to put session, usage, cost, or "what I did"
  information onto a Jira ticket should use this skill so the format and the
  cost/token accounting stay consistent.
---

# Jira session report

Post one comment on a Jira ticket summarizing the Claude Code session: what got
done, plus the session's cost/duration/token metadata. The value is a consistent,
honest record — teammates (and future-you) can see what an agent session cost and
produced without digging through the transcript.

## The one hard rule: never invent the numbers

Cost, durations, code-change counts, and per-model token usage come **only** from
the user's `/usage` output. You cannot read `/usage` yourself — it is a local
Claude Code CLI command with no tool or API behind it. So:

- If the user already pasted their `/usage` **Session** block (they often will),
  use those numbers verbatim.
- If not, ask them to run `/usage` and paste the **Session** section.
- Never estimate or fabricate cost/token/duration figures. If a number isn't in
  what they gave you, omit that line rather than guessing.

Note on delegated work: OpenAI Codex runs (codex-tandem) bill to the ChatGPT
account and do **not** appear in `/usage` — say "billed separately, not
measurable from here" instead of inventing a figure.

## Steps

### 1. Get the `/usage` Session block
Parse these fields from it:
- `Total cost` → total cost
- `Total duration (API)` and `Total duration (wall)` → durations
- `Total code changes` → lines added / removed
- `Usage by model` → per model: input, output, cache read, cache write, and the
  per-model `($cost)`

### 2. Resolve the target ticket
- Default to the Jira key in the current branch name (branches typically start
  with the key, e.g. `PROJ-1234-…`): `git rev-parse --abbrev-ref HEAD`, take the
  leading `<PROJECT>-<NUM>`.
- If the branch has no key, or the user named a different ticket, use theirs.
- Confirm it resolves with `getJiraIssue` (this also gives you the summary to
  reference in the report).

### 3. Resolve the session link
- Prefer the `Claude-Session:` trailer of the latest commit:
  `git log -1 --format=%B | grep -i 'Claude-Session:'`.
- If there's no trailer, use the session id if you know it, otherwise ask.
- Render it as a link when it's a URL.

### 4. Assemble the report
Draw the narrative parts from the session itself (you were there); draw the
metadata from `/usage`. Use the template below. Include a section only when it
applies — don't pad with empty "none" lines for narrative sections (PRs, review,
deploy). For pre-deploy/config facts inside a Deploy note, "none" is fine and
better than silence.

Models: list the primary Claude model(s), and name delegated models (e.g. OpenAI
Codex for implementation/review) and PR review bots (claude[bot], Copilot) when
used — that's part of an honest session record.

### 5. Preview and confirm before posting
Show the composed markdown and get an explicit go-ahead. This comment posts under
the **user's** Jira identity and is visible to the team, so confirm first unless
they've told you to just post it. Every comment ends with the trailer
`🤖 Generated with Claude Code`.

### 6. Post via the Atlassian MCP
The Atlassian tools are deferred — load them first:
`ToolSearch("select:mcp__claude_ai_Atlassian__getAccessibleAtlassianResources,mcp__claude_ai_Atlassian__addCommentToJiraIssue,mcp__claude_ai_Atlassian__getJiraIssue")`

Then:
1. `getAccessibleAtlassianResources` → `cloudId` (pick the right site if there
   are several).
2. `addCommentToJiraIssue` with `cloudId`, `issueIdOrKey`, `commentBody`,
   `contentFormat: "markdown"`.
3. To revise a report you already posted this session, pass `commentId` (from the
   previous call's result) to update in place instead of adding a second comment.

Report the resulting comment link back to the user.

If the Atlassian MCP isn't connected (e.g. a headless/cron run — interactively
authenticated MCP servers can be absent there), say so and hand the user the
composed markdown to paste themselves rather than failing silently.

### 7. Do NOT change ticket status by default
Only transition the ticket (e.g. to Done) if the user explicitly asks. Adding the
report and moving the ticket are separate actions.

## Comment template

```markdown
**Claude Code session report**

<one line: what this session accomplished end-to-end>

**Session info**
- Session: <link or id>
- Duration: <API> (API), <wall> (wall)
- Code changes: +<added> / −<removed> lines
- Models: <primary claude model(s)>; <delegated, e.g. OpenAI Codex for impl/review>; <PR bots if any>

**Usage & cost**

| Model | Input | Output | Cache read | Cache write | Cost |
| --- | --- | --- | --- | --- | --- |
| `claude-fable-5` | 91.9k | 508.6k | 175.7m | 2.5m | $249.00 |
| `claude-opus-4-8` | 46.9k | 316.9k | 156.7m | 1.0m | $96.77 |
| **Total** |  |  |  |  | **$345.78** |

<!-- include only the sections below that apply -->
**Work**
- PRs: <#nums with links>
- Review: <outcomes — Copilot/Claude bot/Codex findings, or "clean">
- Deploy: <one line + pointer to the PR's Deploy section, or "none">

🤖 Generated with Claude Code
```

Keep the top-line facts as bullets and the token accounting as the table — the
table stays readable as models are added. Match the numbers to `/usage` exactly;
if `/usage` reports a total cost that differs from the per-model sum (rounding),
show `/usage`'s total in the Total row.

## Example

**User:** "add this session to PROJ-1234 — here's my /usage: Total cost $345.78,
API 3h 44m, wall 1d 6h, 1735 added / 760 removed, claude-fable-5 91.9k in /
508.6k out / 175.7m cache read / 2.5m cache write ($249.00), claude-opus-4-8
46.9k / 316.9k / 156.7m / 1.0m ($96.77)"

**You:** resolve ticket (PROJ-1234 from the branch or their message), pull the
session link from the last commit's `Claude-Session:` trailer, compose the report
with the table above, show it, confirm, then `addCommentToJiraIssue`.
