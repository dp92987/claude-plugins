# jira-ticket-creator

Create a Jira ticket from what you just discussed, with the team's defaults
applied and a description that stands on its own.

It fills exactly the fields you would otherwise fill by hand: summary,
description, component, labels, story points (a default scale is built into the
skill; the profile can refine or replace it), the
epic in `Parent`, the story's "split to" link, and a sprint when you give its id
or its exact name. Anything you name explicitly wins over the default.

It deliberately does not manage the rest of the ticket: status, assignee,
priority and dates are left alone — the ticket is created in the project's
default status and stays there. `Parent` and the story split are the only links
it creates on its own; `Blocks`, `Relates` and the rest need to be asked for —
with one exception: in a feature batch (a story split into tasks created in one
go) every dependency between the tasks becomes a `Blocks` link, because the
order was agreed together with the task list.

## Profiles: the skill is project-agnostic

Nothing team-specific lives in the skill. The site URL, cloud id, project key,
issue-type/field/link ids, component list, label vocabulary, title format,
story-point conventions, sprint board and ticket language all live in a
**profile** —
a markdown file in the plugin's data directory (`${CLAUDE_PLUGIN_DATA}`,
normally `~/.claude/plugins/data/jira-ticket-creator-<marketplace>/`):

- `config.md` — maps repositories (by normalized `git remote get-url origin`)
  to profiles, exact matches only — no wildcards and no default profile, so a
  ticket can never land in the wrong Jira via a silently guessed profile;
- `profiles/<name>.md` — one profile per team/project, sections named per
  `skills/jira-ticket-creator/references/profile-template.md`.

The contract is "no section — the skill does not manage that field": a profile
without a Labels section simply produces tickets without labels, reported as
such. When the repository has no mapping line, the skill creates nothing and
points at `/jira-ticket-creator:setup`, which interviews you, takes ids from
Jira with a handful of cheap calls, writes the profile and adds the mapping
line. Only an explicit "one-off ticket, no setup" request bypasses this, with
the site and project key asked for and a minimal ticket created.

Writing rules are not profile material and always apply: facts verified in
their primary source, the per-type description forms, no ticket keys in prose,
and the attribution footer.

Ticket keys never appear in the description text. A relation is a Jira link
field: it shows on the board, it drives filters and dependencies, and it stays
correct when someone changes it — a line of prose does none of that. A relation
the skill spots but was not asked for is offered in the report instead of being
written into the body. The one exception is the execution order of a feature
batch: ordering as a whole has no Jira field, so the story gets a numbered
execution-order section once all the keys exist, and each task states its step
right after the `DOD:` line — on top of the `Blocks` links, never instead of
them.

A `Task` states **what** must be done and **where** — how to do it is the
implementer's call. Specifics enter the ticket only when the user supplied them,
and in the form they were given: a requirement stays a requirement, an example
stays an example. When parameters are to be copied from something that already
exists, the ticket carries the pointer ("as in topic X"), never the copied value —
a copied value silently diverges from its source. What never gets dropped is the
localisation (service, file, symbol), the traps, and, for a defect, the mechanism:
those are facts about the system rather than decisions about the work.

The description is the point, and its shape follows the issue type. Two things
hold for every type: the body is written in the profile's language, and it ends
with the attribution footer naming the tool and the model. Past that:

- **`Task`** — free section set: sections exist when there is something true to put
  in them. Each step names the outcome, the localisation and the traps; "what it
  does today / what to change / why" appear only when the decision was actually
  made.
- **`Bug`** — fixed section set, the one every bug tracker ships with: how to
  reproduce, expected vs actual, environment with a date, evidence, and either the
  mechanism or ranked hypotheses. Fixed because a defect has to be reproducible by
  someone else, and reproduction falls apart on any missing detail.
- **`Story`** — a short paragraph plus the links to follow (doc, mockups, thread).
- **`Research`** — a short paragraph plus a `DOD:` naming the artefact it must
  produce.
- **Other types** (`Epic`, `Design`, `QA`, …) — no template at all.

Every fact asserted is verified against its primary source first: the file is
opened, the number is measured and dated or attributed to whoever reported it. An
unverified fact becomes an open question in the ticket, not prose. A decision that
was never made stays open too — that is not the same as a gap.

## Requirements

- The [Atlassian MCP server](https://www.atlassian.com/platform/remote-mcp-server)
  connected in Claude Code.
- A profile in the plugin's data directory — created by
  `/jira-ticket-creator:setup` on first use.

## Usage

Trigger phrases like:

- "создай тикет на это"
- "создай задачку на новый топик", "заведи таску", "накинь тикет на это"
- "заведи задачу и положи в спринт 12345"
- "оформи это багой, эпик ABC-3480"
- "create a jira ticket for this fix"

The skill resolves the profile from the current repository, gathers facts from
the code and the session, picks the fields, writes the description and creates
the ticket straight away — asking first only when an answer is missing that
would make the ticket wrong rather than merely incomplete (no object of work, no
verifiable outcome, or a sprint named only as "the current one"). Missing detail
becomes an "Открытый вопрос" section inside the ticket instead of a round of
chat. After creating it adds the epic parent, the story's "split to" link and
the sprint, then reports the ticket link, the fields, the estimate with its
one-line rationale, and the full description text for you to correct. The report
separates what the create response confirms from what was merely sent —
`parent`, sprint and story points are not echoed back, and the skill says so
rather than claiming they landed.

Naming a story does two things: it creates the "split to" link, and it puts the
new ticket in the story's own epic — otherwise the task drops out of the epic on
the board. The epic is read from the story unless you named one yourself.

Splitting a feature works as a batch: the task list and its execution order are
agreed first, then the tasks are created in that order — so each description can
name its predecessors by key without a second pass. Independent tasks share a
step and get no link between them; when no ordering exists at all, none is
invented.

Lookups are otherwise deliberately absent: issue-type, field and link-type ids
live in the profile, and a wrong key is rejected by the write call itself. Three
reads survive, each on its own condition: the story's epic (name the epic and it
disappears), turning a sprint name into its id (give the id and that one goes
too), and reading a ticket you asked to amend when it is not one this session
created — `description` is overwritten whole, so editing someone else's text
without reading it first would erase the rest.

A defect can also be filed without an investigation: summary, expected vs actual,
`DOD:` and where you saw it, with the reproduce/environment/evidence sections kept
in place and marked "не выяснено" rather than dropped — a missing section reads as
"not applicable", an explicit unknown reads as work to do.

Ticket descriptions end with `🤖 Generated with <tool> (<model>)` — e.g.
`🤖 Generated with Claude Code (Opus 5)` — so a reader can see which model wrote
the spec.

Skills: `jira-ticket-creator`. Commands: `/jira-ticket-creator:setup`.

## Where the section rules come from

Nothing in the format is invented for its own sake. Each part traces to a practice
that is standard in the industry:

| Practice | What it gives the ticket |
| --- | --- |
| **INVEST** (Bill Wake) | one ticket, one independently shippable outcome — and the rule to split what is bigger |
| **Acceptance criteria / Definition of Done** (Scrum) | the `DOD:` line: done is observable from outside, not "done by feel" |
| **Given / When / Then** (BDD, Gherkin) | the shape for criteria that have preconditions |
| **Goals / Non-goals** (engineering design docs) | the explicit "вне скоупа" that stops scope creep |
| **Anatomy of a bug report** (Mozilla, Google bug-writing guides) | the fixed section set for a defect |
| **Data over adjectives** | "7% of orders over 30 days" instead of "often" |
| **Single source of truth** | the ticket reads without chasing links |
| **Small batch size** (continuous delivery) | one ticket, one deployment; ordering spelled out when it matters |

The two sections that are a local specialisation rather than a template import —
"Почему это не вернёт `<риск>`" and "Почему `<причина остаётся>`" — narrow the
design-doc "Risks and mitigations" list down to the single risk the reviewer will
actually raise.

## Scope

One profile covers one Jira project of one team. For another project on the same
site the skill deliberately degrades: it creates a minimal ticket (project,
type, summary, description) and tells you which fields it left unset, rather
than applying the team's profile to a project that does not share it. For
another Jira site it asks for the cloud id instead of guessing.

Retargeting the plugin at your own team means running
`/jira-ticket-creator:setup` — no plugin files need editing.
