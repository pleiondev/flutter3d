#!/usr/bin/env bash
# The nightly's badge: the runs `gh run list` prints, in; a shields.io
# endpoint document, out.
#
#   gh run list --workflow nightly.yml --limit 20 \
#     --json status,conclusion,createdAt,updatedAt | tool/nightly_badge.sh
#
# **Stale after 48 hours with no run**, whatever the last one said. The
# nightly runs on one machine in somebody's room, and when that machine is
# off a badge that kept the last green would be a green nobody earned for
# days. Two nights missed is the line: one can be a reboot.
#
# Green says how many green nights in a row, because the tag waits for
# seven of them and the badge is where that count is read. A run still going
# is neither a night nor a reason to be stale.
#
# `.github/workflows/nightly-badge.yml` runs this after every nightly and
# every six hours between them, so the badge turns stale without a run to
# trigger it. `NIGHTLY_NOW` (seconds since the epoch) stands in for the
# clock in tests.
set -euo pipefail

command -v jq >/dev/null || { echo "needs jq" >&2; exit 2; }

jq --compact-output --argjson now "${NIGHTLY_NOW:-$(date +%s)}" '
  def badge(message; color):
    {schemaVersion: 1, label: "nightly", message: message, color: color};
  (map(select(.status == "completed"))) as $done
  | if length == 0 then badge("never run"; "lightgrey")
    else
      (($now - (map(.createdAt | fromdateiso8601) | max)) / 3600 | floor) as $age
      | if $age >= 48 then
          badge("stale, \($age) h since the last run"; "orange")
        elif ($done | length) == 0 then badge("running"; "lightgrey")
        elif $done[0].conclusion == "success" then
          ([$done[] | .conclusion == "success"] | index(false) // length) as $n
          | badge("passing, \($n) night\(if $n == 1 then "" else "s" end) in a row";
              "brightgreen")
        elif $done[0].conclusion == "failure" then badge("failing"; "red")
        else badge($done[0].conclusion; "lightgrey")
        end
    end
'
