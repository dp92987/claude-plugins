# What a good rule looks like

One sentence. Generalizable beyond the session it came from. Positively phrased —
say what to do, and prefer pointing at an exemplar file over prose ("follow the
pattern in X" beats three sentences of abstract description, and stays true as
the exemplar evolves). Repo-specific rules start with the repo name; general
taste rules don't.

A rule earns its place only if it changes what an agent would otherwise produce.
If any competent agent would already do it, it's noise.

## Good rules

- Storage methods return model types from the models package, not driver types like `bson.Raw`.
- delta: client response handlers mirror `handleLookup` in `cmd/flight-status/api/client.go` — plain `fmt.Errorf(TplRespError, ...)`, no new error sentinels.
- Not-found from storage is a `(value, bool, error)` return, not a sentinel error — see `GetActiveCarpetRestrictionByAirport`.
- PR descriptions state what changed and why in 2–3 sentences; no bullet-list changelogs of every file.

## Bad rules (and why)

- "Write clean, idiomatic Go." — vacuous; changes nothing about agent output.
- "Don't use the wrong error handling." — negative, vague, no exemplar; what's *right*?
- "In PR #23714 the export limit was removed." — one-off event, not a preference; belongs in git history.
- "Use `SetLimit(10_000)` when exporting subscriptions." — task-specific detail masquerading as taste; would be wrong in any other context.

## Ambiguity

If you can't tell whether a correction is general taste or context-specific,
don't guess. In interactive runs, ask (max 5 questions per session). In
non-interactive runs, file it in the inbox with a `QUESTION:` line.
