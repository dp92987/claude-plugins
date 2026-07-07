# jira-session-report

Post a "Claude Code session report" comment on a Jira ticket: a summary of what
the session accomplished (task, PRs, review outcomes, deploy notes) plus the
session metadata — session link, cost, API/wall duration, code-change counts,
and per-model token usage.

The one hard rule: the numbers come only from the user's pasted `/usage` output.
The skill never estimates or fabricates cost, duration, or token figures — if a
number wasn't provided, the line is omitted.

## Requirements

- The [Atlassian MCP server](https://www.atlassian.com/platform/remote-mcp-server)
  connected in Claude Code (used to resolve the ticket and post the comment).

## Usage

Trigger phrases like:

- "add session info to PROJ-1234"
- "post the session report to the ticket"
- "log this session on jira"

The skill resolves the ticket from the current branch name (leading
`<PROJECT>-<NUM>`) unless one is named, pulls the session link from the latest
commit's `Claude-Session:` trailer, asks for your `/usage` Session block if you
haven't pasted it, previews the composed comment, and posts it after your
confirmation. It never transitions the ticket — reporting and status changes are
separate actions.

Skills: `jira-session-report`.
