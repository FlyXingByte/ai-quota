#!/bin/bash
# Keeps the string tables and the code honest with each other.
#
#   missing  — a key the code asks for that no table defines. Ships as a raw
#              identifier in the UI, so this fails the build.
#   orphaned — a key a table defines that no source file mentions. A translation
#              nobody will ever see, quietly going stale.
#
# Two extraction passes, because keys reach L() two ways: written inline, and
# carried in a provider's table of buckets. The strict pass (literals inside an
# L(...) call) drives "missing"; the relaxed pass (any key-shaped literal)
# drives "orphaned", where a false positive costs nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANGS=(en zh-Hans)
KEY_SHAPE='"[a-z][a-z0-9_]*(\.[a-z0-9_]+)+"'
STATUS=0

# Newlines flattened so a call split across lines is still one match, and `L(`
# is required to stand alone so `URL(` does not look like one.
flat="$(cat "$ROOT"/Sources/*.swift | tr '\n' ' ')"
used="$(printf '%s' "$flat" | grep -oE "[^A-Za-z0-9_]L\([^)]*" \
        | grep -oE "$KEY_SHAPE" | tr -d '"' | sort -u)"
mentioned="$(grep -ohE "$KEY_SHAPE" "$ROOT"/Sources/*.swift | tr -d '"' | sort -u)"

for lang in "${LANGS[@]}"; do
  table="$ROOT/Resources/$lang.lproj/Localizable.strings"
  if [ ! -f "$table" ]; then
    echo "缺少字符串表 / missing table: $table" >&2
    exit 1
  fi
  defined="$(grep -oE '^"[a-z0-9_.]+"' "$table" | tr -d '"' | sort -u)"

  missing="$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$defined"))"
  orphaned="$(comm -13 <(printf '%s\n' "$mentioned") <(printf '%s\n' "$defined"))"
  duplicated="$(grep -oE '^"[a-z0-9_.]+"' "$table" | tr -d '"' | sort | uniq -d)"

  for problem in "代码用到但表里没有 / used but undefined:|$missing" \
                 "表里有但代码没提到 / defined but unreferenced:|$orphaned" \
                 "重复的键 / duplicate keys:|$duplicated"; do
    body="${problem#*|}"
    [ -n "$body" ] || continue
    echo "[$lang] ${problem%%|*}" >&2
    printf '%s\n' "$body" | sed 's/^/    /' >&2
    STATUS=1
  done
done

if [ "$STATUS" -eq 0 ]; then
  echo "本地化检查通过 / localization OK ($(printf '%s\n' "$defined" | wc -l | tr -d ' ') keys × ${#LANGS[@]})"
fi
exit "$STATUS"
