<!--
Taste rules: what no linter can judge. This file is not loaded into coding
sessions — it is the input to /style-guard:taste-review, which
checks a diff against it with one subagent per theme.

Written for a reviewer, so every rule must be decidable from a diff.
Group rules under `# <theme>` headings (comments, naming, error handling,
structure …); a theme is the unit of one subagent's attention. Rule ids are
unique across the whole file. Per-rule format:

    ## <id-in-kebab-case>
    **Rule:** imperative, observable — what must or must not appear
    **Why:** the reason, so unanticipated cases still resolve correctly
    **Violation:**
        3-10 lines of code that breaks it
    **Correct:**
        the same thing done right
    **Don't flag:** the legitimate neighbors this rule must stay away from
    **Needs:** full-file  (only when added lines aren't enough to judge)

Rules are added by /style-guard:add, which decides whether a
stated rule belongs here or in one of the two machine-checked tiers.
-->
