#!/usr/bin/env bash
# Decides what Aedis Release Cut may do with the token it received, before the action touches the repository:
#   pr            release pull request (version-files set) with an App or PAT token
#   tag           tag straight on the commit with an App or PAT token: the pushed tag starts the release workflows
#   tag-dispatch  tag with the GITHUB_TOKEN, then `gh workflow run` of dispatch-workflows on the tag (a tag pushed
#                 with the GITHUB_TOKEN starts no workflow; workflow_dispatch is GitHub's exception)
#   tag-silent    tag with the GITHUB_TOKEN and nothing to dispatch: the tag starts nothing, the action says so
# A release pull request with the GITHUB_TOKEN gets no pull_request events (no CI, no gate), so it fails here.
#
# Usage: mode.sh --version-files "<files>" --github-token true|false --dispatch-workflows "<workflow files>"
#        mode.sh --self-test
set -euo pipefail

decide() {
  local files="$1" github="$2" dispatch="$3"
  if [ -n "$files" ]; then
    if [ "$github" = true ]; then
      echo "::error::a release pull request needs a GitHub App or fine-grained PAT token: a pull request opened with the GITHUB_TOKEN gets no pull_request events, so no CI and no merge gate ever run on it. See 'Which token' in https://github.com/aedis-build/aedis-release-cut#which-token" >&2
      return 1
    fi
    echo pr; return 0
  fi
  if [ "$github" != true ]; then echo tag; return 0; fi
  if [ -n "$dispatch" ]; then echo tag-dispatch; else echo tag-silent; fi
}

self_test() {
  local rc=0
  expect() {
    local want="$1" files="$2" github="$3" dispatch="$4" got
    got="$(decide "$files" "$github" "$dispatch" 2>/dev/null || echo fail)"
    if [ "$got" != "$want" ]; then echo "FAIL files='$files' github=$github dispatch='$dispatch' → '$got', want '$want'"; rc=1; fi
  }
  expect tag "" false ""
  expect tag "" false "release.yml"
  expect tag-dispatch "" true "release.yml cli-release.yml"
  expect tag-silent "" true ""
  expect pr "package.json" false ""
  expect pr "package.json packages/cli/package.json" false "release.yml"
  expect fail "package.json" true ""
  expect fail "package.json" true "release.yml"
  [ $rc -eq 0 ] && echo "self-test ok"
  return $rc
}

files="" github=false dispatch=""
case "${1:-}" in
  --self-test) self_test; exit $? ;;
  "") echo "usage: $0 --version-files <files> --github-token true|false --dispatch-workflows <workflows> | --self-test" >&2; exit 2 ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --version-files) files="$2"; shift 2 ;;
    --github-token) github="$2"; shift 2 ;;
    --dispatch-workflows) dispatch="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
decide "$files" "$github" "$dispatch"
