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
      contents: write   # the GITHUB_TOKEN pushes the tag
      actions: write    # and dispatches release.yml on it
    steps:
      - uses: aedis-build/aedis-release-cut@<sha of the release tag> # vX.Y.Z
        with:
          bump: ${{ inputs.bump || 'auto' }}
          dispatch-workflows: release.yml
```

That is the no-secret setup: the version only exists in the tag, the workflow's own `GITHUB_TOKEN` pushes it and,
because a tag pushed with that token starts no workflow, the action runs `release.yml` on the tag with
`gh workflow run`. The `release.yml` accepts that dispatch next to its tag trigger:

```yaml
# .github/workflows/release.yml
on:
  push:
    tags: ["v[0-9]+.[0-9]+.[0-9]+"]
  workflow_dispatch:
    inputs:
      tag:
        description: Tag to release (set by Aedis Release Cut; the run checks out this ref)
        required: false
```

With a GitHub App token the same job needs only `contents: read`, and the pushed tag starts `release.yml` by itself:

```yaml
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
        with:
          token: ${{ steps.app.outputs.token }}
          app-slug: ${{ steps.app.outputs.app-slug }}
          bump: ${{ inputs.bump || 'auto' }}
          # Node/pnpm repository with the version in package.json files: a release pull request, so an App or PAT token.
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

### Inputs

| Input | Default | Meaning |
|---|---|---|
| `token` | `${{ github.token }}` | Token that tags and opens the release PR: a GitHub App installation token, a fine-grained PAT, or the `GITHUB_TOKEN` (tags only; see [Which token](#which-token)) |
| `dispatch-workflows` | `""` | Workflow files run with `gh workflow run` on the new tag when the token is the `GITHUB_TOKEN`, e.g. `release.yml cli-release.yml`; ignored with an App or PAT token |
| `app-slug` | `""` | Slug of the App that issued the token, so commits and tags carry its bot user (`<slug>[bot]`); empty uses `github-actions[bot]` |
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

## Which token

A tag or a pull request made with the workflow's `GITHUB_TOKEN` starts no other workflow: GitHub stops the chain on
purpose. The action decides what it can do with the token it got (`scripts/mode.sh`, before touching the repository)
and the README orders the choices from the simplest to the safest:

1. **`GITHUB_TOKEN` + `dispatch-workflows`** (no secret at all). Only the direct-tag shape (no `version-files`): the
   token pushes the tag, then the action runs each listed workflow on it with `gh workflow run`, GitHub's exception
   to the rule (`workflow_dispatch` and `repository_dispatch` do start from the `GITHUB_TOKEN`). The job needs
   `contents: write` and `actions: write`, and each workflow accepts `workflow_dispatch` with an optional `tag`
   input, as above. Without `dispatch-workflows` the tag is pushed and the run says, in its summary, that nothing
   starts on it. A release pull request is refused in this mode: a pull request opened with the `GITHUB_TOKEN`
   receives no `pull_request` events, so no CI and no merge gate would ever run on it.
2. **Fine-grained personal access token** (`contents` and `pull_requests` write on the repository). Works for both
   shapes and starts the workflows like any push, but it is a long-lived credential of one person, and pushing the
   tag through a ruleset needs that person in the bypass list.
3. **GitHub App** (recommended for organizations). The installation token lives one hour, is scoped to the
   permissions below, names the App's bot user as the author of the tag and the pull request, and the ruleset bypass
   is granted to the App, not to a person. In the Aedis merge gate that App is the one in `trustedAuthors`, distinct
   from the App that reviews: the reviewer never authors, and a pull request authored by the reviewer is refused.

### Creating the App in one click (App Manifest)

[`docs/app-manifest.json`](docs/app-manifest.json) declares the App with exactly the permissions it needs:
`contents: write`, `pull_requests: write`, `metadata: read` and `workflows: write` (only so a release pull request
may touch `.github/workflows`; drop it otherwise). GitHub creates the App from a form that POSTs that manifest to
`https://github.com/organizations/<org>/settings/apps/new` (or `https://github.com/settings/apps/new` for a
personal account): open [`docs/create-app.html`](docs/create-app.html) in a browser, type the organization, submit,
confirm on GitHub, and the App exists with a private key to download. Then install it on the repository, store the
App id and the private key as secrets (`RELEASE_APP_ID`, `RELEASE_APP_PRIVATE_KEY` above), and add the App to the
ruleset's bypass list for the default branch so it can push the tag. The same by hand: *Settings → Developer
settings → GitHub Apps → New GitHub App*, webhook off, the four permissions above, generate a private key.

## Scripts

`scripts/next-version.sh` computes the version (`--self-test` covers every rule above) and
`scripts/check-conventional-commits.sh` validates messages (`--range`, `--file` for a `commit-msg` hook, `--message`,
`--self-test`). They are the single source of the Conventional Commits rule for the Aedis Platform.
`scripts/mode.sh` decides what the token allows (tag, tag + dispatch, release PR, or an early failure); its
`--self-test` covers every combination.

## License

Apache-2.0. See [LICENSE](LICENSE) and [SECURITY.md](SECURITY.md).
