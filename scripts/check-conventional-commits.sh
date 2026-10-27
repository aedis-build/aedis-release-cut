#!/usr/bin/env bash
# Checks that messages follow Conventional Commits (https://www.conventionalcommits.org):
#   <type>(<optional scope>)!?: <description>
# types: feat fix docs style refactor perf test build ci chore revert
# Used by the Aedis Platform conventional-commits.yml workflow (every commit of the PR plus its title) and by the local
# commit-msg hook. The same rule decides what Aedis Release Cut releases (scripts/next-version.sh).
#
# Usage: check-conventional-commits.sh --range <base>..<head> | --file <message file> | --message "<text>" | --self-test
set -euo pipefail
PATTERN='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: [^ ].{0,99}$'

check() {
  local subject="$1"
  case "$subject" in
    "Merge "*|"Revert \""*) return 0 ;;
  esac
  if [[ "$subject" =~ $PATTERN ]]; then return 0; fi
  echo "not a Conventional Commit: '$subject'" >&2
  echo "  expected: <type>(<scope>)!: <description>   types: feat fix docs style refactor perf test build ci chore revert" >&2
  return 1
}

self_test() {
  local rc=0
  expect() {
    local want="$1" subject="$2" got
    if check "$subject" 2>/dev/null; then got=0; else got=1; fi
    if [ "$got" != "$want" ]; then echo "FAIL '$subject' → $got, want $want"; rc=1; fi
  }
  expect 0 "feat(cli): new command"
  expect 0 "fix!: drop x"
  expect 0 "build(deps): bump a from 1 to 2"
  expect 0 "Merge branch 'main' into feature"
  expect 1 "Feat: capitalized type"
  expect 1 "feat(Scope): uppercase scope"
  expect 1 "feat:no space"
  expect 1 "wip"
  expect 1 "feat: $(printf 'x%.0s' $(seq 1 101))"
  [ $rc -eq 0 ] && echo "self-test ok"
  return $rc
}

rc=0
case "${1:-}" in
  --self-test) self_test; exit $? ;;
  --range)
    # Bot commits land by squash with a conventional title; only the title is checked for them
    while IFS=$'	' read -r author subject; do
      [ -n "$subject" ] || continue
      [ "$author" = "dependabot[bot]" ] && continue
      check "$subject" || rc=1
    done < <(git log --no-merges --format='%an%x09%s' "$2")
    ;;
  --file)
    subject="$(grep -v '^#' "$2" | sed -n '1p')"; check "$subject" || rc=1
    ;;
  --message)
    check "$2" || rc=1
    ;;
  *) echo "usage: $0 --range <base>..<head> | --file <msg> | --message <text> | --self-test" >&2; exit 2 ;;
esac
[ $rc -eq 0 ] && echo "conventional commits: ok"
exit $rc
