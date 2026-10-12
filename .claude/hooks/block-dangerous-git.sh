#!/bin/bash

# Read the raw hook input so the check works without jq, which would otherwise let every command through.
INPUT=$(cat)

# Ordinary pushes pass. Force, mirror and remote-delete pushes are blocked, along with the destructive commands below.
DANGEROUS_PATTERNS=(
  'push[^"]*--force'
  'push[^"]* -f( |"|$)'
  'push[^"]*--mirror'
  'push[^"]*--delete'
  'push[^"]* :[^ "]'
  'push[^"]* \+[^ "]'
  'reset --hard'
  'git clean -fd'
  'git clean -f'
  'git branch -D'
  'git checkout (-- )?\.'
  'git restore (--[^ ]+ )*\.'
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if printf '%s' "$INPUT" | grep -qE "$pattern"; then
    echo "BLOCKED: matches dangerous pattern '$pattern'. The user has prevented you from doing this." >&2
    exit 2
  fi
done

exit 0
