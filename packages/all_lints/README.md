# all_lints

[![pub package](https://img.shields.io/pub/v/all_lints.svg)](https://pub.dev/packages/all_lints)
[![standard-readme compliant](https://img.shields.io/badge/readme%20style-standard-brightgreen.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme)
[![Keep a Changelog v1.1.0](https://img.shields.io/badge/changelog-Keep%20a%20Changelog%20v1.1.0-%23E05735)](https://keepachangelog.com/en/1.1.0/)

Analysis options that enable every available Dart lint rule.

For teams that prefer disabling a few select rules, instead of having a huge file with rules to enable.

## Table of Contents

- [Background](#background)
- [Install](#install)
- [Usage](#usage)
- [Known conflicting rule pairs](#known-conflicting-rule-pairs)
- [Maintainers](#maintainers)
- [Contributing](#contributing)
- [License](#license)

## Background

The Dart linter ships ~250 rules. Each rule has a maturity state: `stable`, `experimental`, `deprecated`, or `removed`. This package enumerates them at generation time from the SDK's own `pkg/linter/tool/machine/rules.json`, filters out `deprecated` and `removed`, and emits two flavors:

- **`stable`** — only rules with `state.stable`. Safer; rules in this set won't break on you when the SDK ships new rules behind an experimental flag.
- **`all`** — `stable` plus `experimental`. More coverage; you'll catch new rules earlier, but they may change semantics.

Each flavor comes as a Dart-only file and a Flutter file including Flutter-specific rules. Thes come in two variants:

- **Unversioned** — `dart_all.yaml` / `dart_stable.yaml` / `flutter_all.yaml` / `flutter_stable.yaml` reflect whatever the latest version of `all_lints` was generated against. Upgrading the package gets you new rules.
- **Language-version pinned** — `dart_all_3_11.yaml` / `flutter_stable_3_11.yaml` and so on are frozen snapshots for a specific Dart language version. They do not change once published.

Some rules in the Dart linter are mutually exclusive. `all_lints` leaves it to you to disable the ones you don't want.

## Install

```sh
dart pub add --dev all_lints
```

## Usage

Add an `include:` directive to your project's `analysis_options.yaml`:

```yaml
# Track latest. Pure-Dart project, every non-deprecated rule:
include: package:all_lints/dart_all.yaml

# Same, stable-only:
include: package:all_lints/dart_stable.yaml

# Flutter project (transitively includes the matching dart_*.yaml):
include: package:all_lints/flutter_all.yaml
include: package:all_lints/flutter_stable.yaml

# Pinned to a specific Dart language version (e.g. 3.11):
include: package:all_lints/dart_all_3_11.yaml
include: package:all_lints/flutter_stable_3_11.yaml
# …etc.
```

Pinned files are shipped for Dart language versions **3.2+**.

Pick **unversioned** if you want lint coverage to follow Dart forward as you upgrade the package. Pick **pinned** if you want a stable rule set across package upgrades — useful for monorepos and teams that don't want a Dart upgrade to surface a wave of new lints in the same PR.

To disable a specific rule (after including any of the above):

```yaml
include: package:all_lints/all.yaml

linter:
  rules:
    prefer_double_quotes: false
    always_specify_types: false
```

## Maintainers

[@tjarvstrand](https://github.com/tjarvstrand)

## Contributing

PRs and issues welcome. The repository is a Dart pub workspace with two packages:

- `packages/all_lints` (this package, published to pub.dev) — only the generated YAML files plus this README, CHANGELOG, LICENSE.
- `packages/all_lints_generator` (private, `publish_to: none`) — `tool/generate.dart`, smoke tests, and dev dependencies.

To regenerate the YAML files after a Dart SDK bump, run from the repo root:

```sh
mise install
mise run generate
mise run test
```

The generator fetches `pkg/linter/tool/machine/rules.json` from the dart-lang/sdk repo at the version pinned in `mise.toml`, so bumping the SDK is a `mise.toml` edit followed by `mise run generate`. Pinned files (`all_<M>_<m>.yaml`, `stable_<M>_<m>.yaml`) are frozen.

## License

[MIT](LICENSE) © Thomas Järvstrand
