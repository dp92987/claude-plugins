#!/usr/bin/env bash
# Distill a Claude Code session JSONL to the parts that can carry style signal:
# every genuine user message ([user]) and every edit/plan rejection ([rejection]).
#
# Deliberately NOT selective beyond that: sessions carry at most ~100 genuine user
# messages, so filtering them by correction keywords buys nothing and measurably
# drops signal — corrections phrased as "rename X", "remove Y", "ive made some
# changes, update the code" carry no keyword. Judging what is a correction is the
# model's job; this script only strips the transcript bulk (tool results,
# assistant output, meta messages) so Mode 1 reads kilobytes instead of megabytes.
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

  .[]
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
      | "--- [rejection]\n" + ($feedback | .[0:3000])
    else
      text_of(.) as $text
      | select($text != ""
          and ($text | startswith("[Request interrupted") | not)
          and ($text | startswith("<local-command") | not)
          and ($text | startswith("<command-name>") | not)
          and ($text | startswith("<command-message>") | not)
          and ($text | startswith("<task-notification>") | not)
          and ($text | startswith("<system-reminder>") | not)
          and ($text | startswith("<bash-input>") | not)
          and ($text | startswith("<bash-stdout>") | not)
          and ($text | startswith("Caveat:") | not))
      | "--- [user]\n" + ($text | .[0:3000])
    end
' "$TRANSCRIPT"
