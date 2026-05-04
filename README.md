# all_lints workspace

This is a Dart pub workspace containing two packages:

| Path | Published? | Purpose |
|---|---|---|
| [`packages/all_lints`](packages/all_lints/) | yes — [`all_lints` on pub.dev](https://pub.dev/packages/all_lints) | Generated `analysis_options.yaml` files. |
| [`packages/all_lints_generator`](packages/all_lints_generator/) | no (`publish_to: none`) | Generator script + smoke tests. |

The published package is consumer-facing — see its [README](packages/all_lints/README.md) for usage. The generator is a maintainer tool that fetches `pkg/linter/tool/machine/rules.json` from the Dart SDK at the version pinned in `mise.toml` and writes the YAML files into the published package's `lib/`.

## Maintainer commands

Run from the repo root:

```sh
mise install         # install the Dart version pinned in mise.toml
mise run generate    # regenerate packages/all_lints/lib/*.yaml
mise run test        # smoke tests
mise run analyze     # dart analyze across the workspace
```

`mise run` auto-installs Dart packages on demand via the [`dart` deps provider](https://mise.jdx.dev/dev-tools/deps.html).

## Nightly auto-release

`.github/workflows/nightly.yml` runs daily at 04:17 UTC (and on `workflow_dispatch`):

1. Reads the latest stable Dart SDK from `dart-lang/sdk` releases (or accepts a `target_sdk` workflow input).
2. If `packages/all_lints/lib/dart_all_<major>_<minor>.yaml` already exists for the target's language version, the workflow exits — pinned files for that minor are frozen, so there's nothing new to ship. Patch releases of an existing minor are also no-ops.
3. Otherwise, runs `tool/generate.dart --sdk-version=<latest>` (the running Dart version doesn't need to match the target — the generator just fetches `rules.json` from GitHub for the target version).
4. Bumps the package's patch version, prepends a CHANGELOG entry, commits, tags `v<version>`, pushes, and triggers the pub.dev publish job.

The workflow refuses to publish if `## [Unreleased]` has any pending entries — manually move them into a versioned section first.

### One-time setup

Required on pub.dev (admin / package owner action):

1. Sign in to [pub.dev](https://pub.dev) and open the `all_lints` package's **Admin** tab.
2. Under **Automated publishing**, enable GitHub Actions:
   - Repository: `tjarvstrand/all_lints`
   - Tag pattern: `v{{version}}`
   - Require environment: leave empty (or set to a name and add it under **Settings → Environments** in GitHub).
3. Save.

After that, the publish job in the workflow uses OIDC and needs no further secrets. See [Automated publishing on pub.dev](https://dart.dev/tools/pub/automated-publishing) for full details.
