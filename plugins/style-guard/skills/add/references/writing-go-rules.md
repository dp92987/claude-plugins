# Writing ast-grep rules for Go

Verified against ast-grep 0.45.1 / tree-sitter-go, 2026-08. Everything below
was hit on real rules — read before drafting, it saves the probe round-trips.

## Probing the tree

When unsure what a construct parses into, dump it:

```
ast-grep run -p 'func $F($$$) $$$' --debug-query=cst file.go   # pattern's own tree
ast-grep scan -c sgconfig.yml --report-style short --color never file.go
```

The scan loop against a fixture is the ground truth; node-kind names below are
a starting map, not a substitute for checking.

## Node kinds cheat sheet (tree-sitter-go)

| Construct | kind | Useful fields |
|---|---|---|
| `func f(...) ...` | `function_declaration` | `name`, `parameters`, `result`, `body` |
| `func (r T) m(...)` | `method_declaration` | `receiver`, `name`, `parameters` |
| parameter list | `parameter_list` | children: `parameter_declaration` |
| one parameter | `parameter_declaration` | children: identifier(s) + the type node |
| `api.Order` | `qualified_type` | regex on full text, e.g. `"^api\\."` |
| `Order` (local/bare) | `type_identifier` | discriminates local vs imported types |
| `*T` | `pointer_type` | wraps the inner type node |
| `[]T` | `slice_type` | wraps the inner type node |
| `map[K]V` | `map_type` | |
| call `foo(x)` | `call_expression` | `function`, `arguments` |
| `pkg.Fn(x)` call target | `selector_expression` | inside `call_expression` |
| import spec | `import_spec` | path as `interpreted_string_literal` |

Key discriminator learned on the free-functions rule: a type from the same
package appears as bare `type_identifier`, an imported one as
`qualified_type` — that distinction alone encodes "could this even be a
method here" without type analysis.

## Mechanics that bite

- **A bare call pattern doesn't parse at top level.** `pattern:
  fmt.Println($$$)` silently matches nothing — tree-sitter parses the bare
  expression as `qualified_type` + ERROR. Wrap it in a context and select the
  node you mean:

  ```yaml
  pattern:
    context: 'func f() { fmt.Println($$$ARGS) }'
    selector: call_expression
  ```

  Applies to any statement/expression pattern that isn't a valid top-level Go
  declaration. Check suspicious patterns with `--debug-query=cst`.

- **`ast-grep test` is the built-in alternative to a hand-run fixture**: a
  `rule-tests/<id>-test.yml` with `valid:`/`invalid:` snippet lists, run via
  `ast-grep test -c sgconfig.yml` (add `testConfigs:` to the config). Same
  discipline, machine-checked both directions — prefer it when the rule will
  live long enough to be tuned.

- **`has` matches direct children only by default.** To reach a type wrapped
  in `pointer_type`/`slice_type`, add `stopBy: end`:

  ```yaml
  has:
    stopBy: end
    kind: qualified_type
    regex: "^api\\."
  ```

  Side effect: `stopBy: end` also matches inside slices/maps of the type —
  decide whether that's wanted per rule.

- **`nthChild` counts all named children.** To count only parameters, scope it:

  ```yaml
  nthChild:
    position: 1
    ofRule:
      kind: parameter_declaration
  ```

- **Positional noise.** "Model as 2nd parameter" fires on `f(a client.X, b
  api.Y)` too; if the intent was the `ctx`-first idiom, require pos-1 to be
  `context.Context` via `all:` of two `has:` clauses on `parameters`.

- **Path exclusions live at rule top level**, not inside `rule:`:

  ```yaml
  ignores:
    - "**/*_test.go"
    - "**/mappers/**"
  ```

  `files:` (allowlist globs) is the inverse for path-scoped rules.

- **Exit codes**: scan exits 1 only when an `error`-severity rule matched;
  `warning` findings exit 0. The hook keys off non-empty stdout, so warnings
  reach the agent — don't escalate severity just to "make it work".

- **`not` + `has` on a field** excludes by declaration name:

  ```yaml
  not:
    has:
      field: name
      regex: "^(new|map|build)"
  ```

## Fixture discipline

One fixture file per rule, containing in this order: every violation shape
(value, pointer, ctx-first if applicable), then every legitimate neighbor
(constructor, mapper, method, local type, test-shaped code). Comment each
case with the expected outcome in Russian. Expected hits are then a fixed
line-number set — compare with:

```
ast-grep scan -c sgconfig.yml --report-style short --color never fixture.go \
  | grep -oP 'fixture\.go:\d+'
```
