# Aedis Release Cut

GitHub Action that cuts the next [semver](https://semver.org) release of a repository from its
[Conventional Commits](https://www.conventionalcommits.org): on every push to the default branch it reads the commits
since the last tag and either **tags** the commit or **proposes a release pull request** that bumps the version files.
Part of the [Aedis Platform](https://github.com/aedis-build/aedis-platform), usable on its own.

| Commits since the last tag | Increment |
|---|---|
| `type!:` or a `BREAKING CHANGE` footer | major |
| `feat` | minor |
| `fix`, `perf`, `refactor`, `revert`, `build(deps)` | patch |
| only `docs`, `ci`, `chore`, `test`, `style` | no release |

Two repository shapes:

- **Without `version-files`** (the version only exists in the tag: a .NET library, an action, a platform): the next tag
  `vX.Y.Z` goes straight on the current commit.
- **With `version-files`** (`package.json` whose `version` follows the release): the version is proposed in a pull
  request `chore(release): vX.Y.Z` that bumps those files, the exact `pin-dependency` inside them, one source file
  (`version-source` with `version-source-pattern`), the `<pin-pattern>X.Y.Z` pins in the docs and, with
  `lockfile-command`, the lockfile. The PR goes through the same CI and review as any change; when it merges, the action
  tags the merged commit (one tag per prefix in `tag-prefixes`) and the repository's release workflows take over.

Nothing is proposed before the first tag exists: cut the first release on purpose, with the `bump` input of a manual
run. It keeps the version the sources already declare when that is higher than the computed one.

## Usage

```yaml
# .github/workflows/release-cut.yml
name: release-cut

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      bump:
        type: choice
        options: [auto, patch, minor, major]
        default: auto

permissions: {}

concurrency:
  group: release-cut
  cancel-in-progress: false

jobs:
  cut:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3.3.0
        id: app
        with:
          app-id: ${{ secrets.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
          permission-contents: write
          permission-pull-requests: write
      - uses: aedis-build/aedis-release-cut@<sha of the release tag> # vX.Y.Z
        id: cut
        with:
          token: ${{ steps.app.outputs.token }}
          app-slug: ${{ steps.app.outputs.app-slug }}
          bump: ${{ inputs.bump || 'auto' }}
          # Node/pnpm repository with the version in package.json files:
          tag-prefixes: v cli-v
          version-files: package.json packages/cli/package.json
          pin-dependency: "@aedis/cli"
          version-source: packages/cli/src/cli.ts
          version-source-pattern: 'export const VERSION = "{version}";'
          pin-pattern: "@aedis/cli@"
          lockfile-command: pnpm install --lockfile-only
```

Pin the action by the commit SHA of a release tag with the tag in the comment, as above: Dependabot
(`package-ecosystem: github-actions`) then opens the repin pull request at every release, SHA and comment together.
The repository's `release.yml` triggers on `push: tags` (or reads the `tag` output of this step) and publishes.

### Inputs

| Input | Default | Meaning |
|---|---|---|
| `token` | required | Installation token of the GitHub App that tags and opens the release PR (`contents: write`, `pull-requests: write`) |
| `app-slug` | `""` | Slug of that App, so commits and tags carry its bot user (`<slug>[bot]`); empty uses `github-actions[bot]` |
| `bump` | `auto` | `auto` from the commits, or `patch`/`minor`/`major`; any of the three also cuts the first release |
| `tag-prefixes` | `v` | Space-separated prefixes; the first names the release (`git describe`, PR title). E.g. `v cli-v` |
| `version-files` | `""` | Space-separated `package.json` files whose `version` follows the release; the first is the current version. Empty tags directly |
| `pin-dependency` | `""` | Dependency pinned exactly to the released version inside `version-files` |
| `version-source` | `""` | Source file that declares the version; needs `version-source-pattern` |
| `version-source-pattern` | `""` | Literal text with `{version}` in place of the version, e.g. `export const VERSION = "{version}";` |
| `pin-pattern` | `""` | Literal prefix whose `<pin-pattern><current version>` occurrences in versioned files move to the new version; lockfiles are left out |
| `lockfile-command` | `""` | Command that regenerates the lockfile after the bump, e.g. `pnpm install --lockfile-only` |
| `node-version` | `22` | Node.js used to read and bump the version files |

### Outputs

| Output | Meaning |
|---|---|
| `tag` | First tag pushed by this run; empty when only a pull request was made or there was nothing to release |

The action checks the repository out itself (full history, so `git describe` sees the tags) and leaves no credential
behind: the token goes in a Git HTTP header for the pushes and never in a URL. A nested checkout under the workspace
is excluded before the release commit, so it can never land as a gitlink without `.gitmodules`.

## Why a GitHub App token, not the GITHUB_TOKEN

A tag or a pull request made with the workflow's `GITHUB_TOKEN` starts no other workflow: GitHub stops the chain on
purpose, so the `release.yml` that should build and publish the tag would never run. A personal access token would
work, but it is a long-lived credential of one person. The installation token of a GitHub App lives one hour, is
scoped to the permissions above, names the App's bot user as the author of the tag and the pull request, and its runs
start the release workflows like any push. In the Aedis merge gate that App is the one in `trustedAuthors`, distinct
from the App that reviews: the reviewer never authors, and a pull request authored by the reviewer is refused.

## Scripts

`scripts/next-version.sh` computes the version (`--self-test` covers every rule above) and
`scripts/check-conventional-commits.sh` validates messages (`--range`, `--file` for a `commit-msg` hook, `--message`,
`--self-test`). They are the single source of the Conventional Commits rule for the Aedis Platform.

## License

Apache-2.0. See [LICENSE](LICENSE) and [SECURITY.md](SECURITY.md).
