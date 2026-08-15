# jira-ticket-creator

Create a Jira ticket from what you just discussed, with the team's defaults
applied and a description that stands on its own.

It fills exactly the fields you would otherwise fill by hand: summary,
description, component (`Backend` by default), one type label plus a label per
affected project, story points on the team's published scale (`Task` and `Bug`
only), the epic in `Parent`, the story's "split to" link, and a sprint when you
give its id or its exact name. Anything you name explicitly wins over the default.

It deliberately does not manage the rest of the ticket: status, assignee,
priority and dates are left alone — the ticket is created in `Inbox` and stays
there. `Parent` and the story split are the only links it creates on its own;
`Blocks`, `Relates` and the rest need to be asked for.

Ticket keys never appear in the description text. A relation is a Jira link
field: it shows on the board, it drives filters and dependencies, and it stays
correct when someone changes it — a line of prose does none of that. A relation
the skill spots but was not asked for is offered in the report instead of being
written into the body.

A `Task` states **what** must be done and **where** — how to do it is the
implementer's call. Specifics enter the ticket only when the user supplied them,
and in the form they were given: a requirement stays a requirement, an example
stays an example. When parameters are to be copied from something that already
exists, the ticket carries the pointer ("as in topic X"), never the copied value —
a copied value silently diverges from its source. What never gets dropped is the
localisation (service, file, symbol), the traps, and, for a defect, the mechanism:
those are facts about the system rather than decisions about the work.

The description is the point, and its shape follows the issue type. Two things hold
for every type: the body is written in Russian, and it ends with the attribution
footer naming the tool and the model. Past that:

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
- **`Epic`, `Design`, `QA`** — no template at all.

Every fact asserted is verified against its primary source first: the file is
opened, the number is measured and dated or attributed to whoever reported it. An
unverified fact becomes an open question in the ticket, not prose. A decision that
was never made stays open too — that is not the same as a gap.

## Requirements

- The [Atlassian MCP server](https://www.atlassian.com/platform/remote-mcp-server)
  connected in Claude Code.

## Usage

Trigger phrases like:

- "создай тикет на это"
- "создай задачку на новый топик", "заведи таску", "накинь тикет на это"
- "заведи задачу в PX и положи в спринт 29280"
- "оформи это багой, эпик PX-3480"
- "create a jira ticket for this fix"

The skill gathers facts from the code and the session, picks the fields, writes
the description and creates the ticket straight away — asking first only when an
answer is missing that would make the ticket wrong rather than merely incomplete
(no object of work, no verifiable outcome, or a sprint named only as "the current
one"). Missing detail becomes an "Открытый вопрос" section
inside the ticket instead of a round of chat. After creating it adds the epic
parent, the story's "split to" link and the sprint, then reports the ticket link,
the fields, the estimate with its one-line rationale, and the full description text
for you to correct. The report separates what the create response confirms from
what was merely sent — `parent`, sprint and story points are not echoed back, and
the skill says so rather than claiming they landed.

Naming a story does two things: it creates the "split to" link, and it puts the
new ticket in the story's own epic — otherwise the task drops out of the epic on
the board. The epic is read from the story unless you named one yourself.

Lookups are otherwise deliberately absent: issue-type, field and link-type ids
live in the skill's reference file, and a wrong key is rejected by the write call
itself. Three reads survive, each on its own condition: the story's epic (name the
epic and it disappears), turning a sprint name into its id (give the id and that
one goes too), and reading a ticket you asked to amend when it is not one this
session created — `description` is overwritten whole, so editing someone else's
text without reading it first would erase the rest.

A defect can also be filed without an investigation: summary, expected vs actual,
`DOD:` and where you saw it, with the reproduce/environment/evidence sections kept
in place and marked "не выяснено" rather than dropped — a missing section reads as
"not applicable", an explicit unknown reads as work to do.

Ticket descriptions end with `🤖 Generated with <tool> (<model>)` — e.g.
`🤖 Generated with Claude Code (Opus 5)` — so a reader can see which model wrote
the spec.

Skills: `jira-ticket-creator`.

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

This is a PX-only skill. Issue-type ids, custom-field ids, the component list, the
label vocabulary, the sprint board, the story-point scale and the cloud id are all
recorded for project `PX` on `aviasales.atlassian.net`, and they sit in both
`SKILL.md` and `skills/jira-ticket-creator/references/fields.md`.

For another project on the same site the skill deliberately degrades: it creates a
minimal ticket (project, type, summary, description) and tells you which fields it
left unset, rather than applying the PX profile to a project that does not share
it. For another Jira site it asks for the cloud id instead of guessing.

Retargeting it at your own project therefore means editing both files — not one.
