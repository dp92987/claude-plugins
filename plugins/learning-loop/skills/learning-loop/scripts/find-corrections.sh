#!/usr/bin/env bash
# Pre-filter a Claude Code session JSONL for correction signals so Mode 1 reads
# filtered signal instead of the raw transcript.
#
# Emits user messages that (a) immediately follow an assistant message containing
# a file-edit tool call, or (b) contain correction keywords. Each block is prefixed
# with [after-edit] and/or [keyword] and truncated to 1500 chars.
#
# Usage: find-corrections.sh <transcript.jsonl>
set -euo pipefail

TRANSCRIPT="${1:?usage: find-corrections.sh <transcript.jsonl>}"
[ -f "$TRANSCRIPT" ] || { echo "no such file: $TRANSCRIPT" >&2; exit 1; }

jq -rs '
  def text_of(m):
    (m.message.content // "")
    | if type == "string" then .
      elif type == "array" then ([.[] | select(.type? == "text") | .text] | join("\n"))
      else "" end;

  def has_edit_tool(m):
    ((m.message.content // []) | type == "array")
    and any((m.message.content)[];
        .type? == "tool_use"
        and (.name == "Edit" or .name == "Write" or .name == "MultiEdit" or .name == "NotebookEdit"));

  def is_tool_result(m):
    ((m.message.content // []) | type == "array")
    and any((m.message.content)[]; .type? == "tool_result");

  def tool_result_text(m):
    [ (m.message.content // [])[]
      | select(.type? == "tool_result")
      | (.content // "")
      | if type == "string" then .
        elif type == "array" then ([.[] | select(.type? == "text") | .text] | join("\n"))
        else "" end
    ] | join("\n");

  [ .[] | select(.type == "user" or .type == "assistant") ] as $msgs
  | range(0; $msgs | length) as $i
  | $msgs[$i]
  | select(.type == "user" and ((.isMeta // false) | not))
  | if is_tool_result(.) then
      # rejections (plan/edit denials) carry user feedback inside tool_result content
      tool_result_text(.) as $text
      | select($text | test("^The user doesn.t want to proceed|^The user wants to clarify"))
      | ($text | split("the user said:")) as $parts
      | select($parts | length > 1)
      | ($parts | last
         | sub("\\s*Note: The user.s next message[\\s\\S]*$"; "")
         | sub("^\\s+"; "")) as $feedback
      | select($feedback != "")
      | "--- [rejection]\n" + ($feedback | .[0:1500])
    else
      text_of(.) as $text
      | select($text != ""
          and ($text | startswith("[Request interrupted") | not)
          and ($text | startswith("<local-command") | not)
          and ($text | startswith("<command-name>") | not)
          and ($text | startswith("<task-notification>") | not)
          and ($text | startswith("<system-reminder>") | not)
          and ($text | startswith("<bash-input>") | not)
          and ($text | startswith("<bash-stdout>") | not)
          and ($text | startswith("Caveat:") | not))
      | (if $i > 0 then $msgs[$i - 1] else null end) as $prev
      | ($prev != null and $prev.type == "assistant" and has_edit_tool($prev)) as $after_edit
      | ($text | test("(?i)(^|\\s)(no|nope|not like this|actually|instead|wrong|dont|don['\''’]t|shouldnt|shouldn['\''’]t|revert|undo|rather|stop|fix this|why did you|нет|не так|не надо|вместо|переделай)(\\s|[.,:!]|$)")) as $keyword
      | select($after_edit or $keyword)
      | "---"
        + (if $after_edit then " [after-edit]" else "" end)
        + (if $keyword then " [keyword]" else "" end)
        + "\n"
        + ($text | .[0:1500])
    end
' "$TRANSCRIPT"
