# jira-ticket-creator

Create a Jira ticket from what you just discussed, with the team's defaults
applied and a description that stands on its own.

Fields come from a default profile (project `PX`, type `Task`/`Bug`, status
`Inbox`, component `Backend`, one type label + one project label, Fibonacci story
points, epic in `Parent`, story linked as "split from", sprint only on request).
Anything the user names explicitly wins over the default.

The description is the point. It is written in Russian in two layers:

- an unheaded intro paragraph for a human — what is broken, who it hurts, the
  measured scale, and a one-line `DOD:`;
- a technical spec for whoever implements it, human or agent — repository, file,
  method, current code, what to change and why, the exemplar to follow, the traps
  that break a naive implementation, the tests to write, and which branch to base
  the work off.

Every fact in it is verified against its primary source before it is written: the
file is opened, the number is measured and dated, the referenced Jira key is
fetched. An unverified fact becomes an open question in the ticket, not prose.

## Requirements

- The [Atlassian MCP server](https://www.atlassian.com/platform/remote-mcp-server)
  connected in Claude Code.

## Usage

Trigger phrases like:

- "создай тикет на это"
- "заведи задачу в PX и закинь в текущий спринт"
- "оформи это багой, эпик PX-3480"
- "create a jira ticket for this fix"

The skill gathers facts from the code and the session, picks the fields, writes
the description, then shows the whole draft — title, fields, story-point estimate
with a one-line rationale, full body — and waits for your go-ahead before it
creates anything. After creating it adds the epic parent, the "split from" link
and the sprint, verifies what actually landed, and reports the ticket link plus
any field Jira rejected.

Ticket descriptions end with `🤖 Generated with <tool> (<model>)` — e.g.
`🤖 Generated with Claude Code (Opus 5)` — so a reader can see which model wrote
the spec.

Skills: `jira-ticket-creator`.

## Adapting it to another project

The PX-specific values — cloud id, issue-type ids, custom-field ids, components,
label vocabulary, status chain, sprint board — live in
`skills/jira-ticket-creator/references/fields-and-transitions.md`. Point that file at
your own project and the workflow carries over unchanged.
