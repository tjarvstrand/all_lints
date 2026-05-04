# Example

A minimal project consuming `all_lints`.

## `pubspec.yaml`

```yaml
name: my_app
environment:
  sdk: ^3.11.0

dev_dependencies:
  all_lints: ^0.1.0
```

## `analysis_options.yaml`

Pick one `include:`. The first segment of the filename selects the project type, the second selects rule maturity, and the optional `_<M>_<m>` suffix pins to a specific Dart language version.

### Pure Dart project

```yaml
include: package:all_lints/dart_all.yaml

# Disable rules you don't want. all_lints intentionally enables both rules in
# each mutually-exclusive pair (e.g. prefer_single_quotes vs
# prefer_double_quotes) and leaves the choice to the consumer.
linter:
  rules:
    prefer_double_quotes: false
    always_specify_types: false
    public_member_api_docs: false
```

### Flutter project

```yaml
include: package:all_lints/flutter_all.yaml
```

`flutter_all.yaml` includes `dart_all.yaml` transitively and adds the 12 Flutter-specific rules (`use_key_in_widget_constructors`, `avoid_unnecessary_containers`, etc.).

## Pinning to a Dart language version

If you'd rather have a stable rule set across `all_lints` upgrades — useful for monorepos or teams that don't want a Dart upgrade to surface a wave of new lints in the same PR — include a versioned file instead:

```yaml
include: package:all_lints/dart_all_3_11.yaml
# or
include: package:all_lints/flutter_stable_3_11.yaml
```

Available pins: `3_2`, `3_3`, `3_4`, `3_5`, `3_6`, `3_7`, `3_8`, `3_9`, `3_10`, `3_11`. Combine with the `dart_`/`flutter_` prefix and `stable`/`all` variant of your choice.

## Stable-only

Drop experimental rules entirely:

```yaml
include: package:all_lints/dart_stable.yaml
# or
include: package:all_lints/flutter_stable.yaml
```
