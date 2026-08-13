# jira-ticket-creator

Create a Jira ticket from what you just discussed, with the team's defaults
applied and a description that stands on its own.

Fields come from a default profile (project `PX`, type `Task`/`Bug`, status
`Inbox`, component `Backend`, one type label plus a label per affected project,
story points on the team's published scale and only for `Task`/`Bug`, epic in
`Parent`, story linked to its children as "split to", sprint only on request, no
assignee). Anything the user names explicitly wins over the default. `Parent` and
the story split are the only links it creates on its own — `Blocks`, `Relates` and
the rest need to be asked for.

A `Task` states **what** must be done and **where** — how to do it is the
implementer's call. Specifics enter the ticket only when the user supplied them,
and in the form they were given: a requirement stays a requirement, an example
stays an example. When parameters are to be copied from something that already
exists, the ticket carries the pointer ("as in topic X"), never the copied value —
a copied value silently diverges from its source. What never gets dropped is the
localisation (service, file, symbol), the traps, and, for a defect, the mechanism:
those are facts about the system rather than decisions about the work.

The description is the point, and its shape follows the issue type. Every type is
written in Russian, opens with an unheaded paragraph for a human, carries a
one-line `DOD:`, names the branch to base the work off, and ends with the
attribution footer. Past that:

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
- "заведи задачу в PX и закинь в текущий спринт"
- "оформи это багой, эпик PX-3480"
- "create a jira ticket for this fix"

The skill gathers facts from the code and the session, picks the fields, writes
the description and creates the ticket straight away — asking first only when an
answer is missing that would make the ticket wrong rather than merely incomplete
(no object of work or no verifiable outcome, no future sprint on the board, an
ambiguous assignee name). Missing detail becomes an "Открытый вопрос" section
inside the ticket instead of a round of chat. After creating it adds the epic
parent, the story's "split to" link and the sprint, then reports the ticket link,
the fields that actually landed, the estimate with its one-line rationale, and the
full description text for you to correct.

Lookups are deliberately absent: issue-type, field and link-type ids live in the
skill's reference file, a wrong key is rejected by the write call itself, and the
create response already carries the resulting fields. The one unavoidable read is
the active sprint id, and only when a sprint was requested.

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
label vocabulary, the status chain, the sprint board, the story-point scale and the
cloud id are all recorded for project `PX` on `aviasales.atlassian.net`, and they
sit in both `SKILL.md` and
`skills/jira-ticket-creator/references/fields-and-transitions.md`.

For another project on the same site the skill deliberately degrades: it creates a
minimal ticket (project, type, summary, description) and tells you which fields it
left unset, rather than applying the PX profile to a project that does not share
it. For another Jira site it asks for the cloud id instead of guessing.

Retargeting it at your own project therefore means editing both files — not one.
