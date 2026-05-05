/// Regenerates eight checked-in YAML files per run from
/// `pkg/linter/tool/machine/rules.json` shipped with the Dart SDK:
///
///   dart_stable[_<M>_<m>].yaml   — Dart-only stable rules
///   dart_all[_<M>_<m>].yaml      — Dart-only stable + experimental
///   flutter_stable[_<M>_<m>].yaml — `include:` the matching dart_ file plus Flutter-specific stable rules
///   flutter_all[_<M>_<m>].yaml    — `include:` the matching dart_ file plus Flutter-specific stable+experimental rules
///
/// Plus an unversioned variant of each (the four files without the `_<M>_<m>` suffix).
///
/// Source of truth: the Dart SDK monorepo at the version pinned by mise. We
/// fetch the file from raw.githubusercontent.com at the matching tag rather
/// than depend on the `linter` package on pub.dev (which has been
/// discontinued and stuck at 1.30.1 since 2023). `rules.json` is checked in
/// from SDK 3.2 onward; earlier SDKs ship no machine-readable rule data.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const _publishedPackageRoot = String.fromEnvironment('ALL_LINTS_PACKAGE_ROOT');

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final overwritePinned = args.contains('--overwrite-pinned');
  final sdkOverride = _flagValue(args, '--sdk-version');
  final languageOverride = _flagValue(args, '--language-version');

  final sdkVersion = sdkOverride ?? _currentSdkVersion();
  final languageVersion = languageOverride ?? _languageVersionOf(sdkVersion);

  stderr.writeln('Dart SDK version:      $sdkVersion');
  stderr.writeln('Dart language version: $languageVersion');

  final rulesUri = Uri.https(
    'raw.githubusercontent.com',
    '/dart-lang/sdk/$sdkVersion/pkg/linter/tool/machine/rules.json',
  );
  stderr.writeln('Fetching:              $rulesUri');
  final rulesJson = await _fetch(rulesUri);

  final rules = _parseRules(rulesJson);
  stderr.writeln('Parsed ${rules.length} rules from rules.json');

  final dartStable = rules.where((r) => r.bucket == _Bucket.stable && !r.isFlutter).map((r) => r.name).toList()..sort();
  final dartAll = rules.where((r) => r.bucket != _Bucket.excluded && !r.isFlutter).map((r) => r.name).toList()..sort();
  final flutterStable = rules.where((r) => r.bucket == _Bucket.stable && r.isFlutter).map((r) => r.name).toList()
    ..sort();
  final flutterAll = rules.where((r) => r.bucket != _Bucket.excluded && r.isFlutter).map((r) => r.name).toList()
    ..sort();
  final excluded = rules.where((r) => r.bucket == _Bucket.excluded).toList()..sort((a, b) => a.name.compareTo(b.name));

  stderr.writeln('  dart stable / all:    ${dartStable.length} / ${dartAll.length}');
  stderr.writeln('  flutter stable / all: ${flutterStable.length} / ${flutterAll.length}');
  stderr.writeln(
    '  excluded:             ${excluded.length} '
    '(deprecated/removed/internal — see list below)',
  );
  for (final r in excluded) {
    stderr.writeln('    - ${r.name} (${r.exclusionReason})');
  }

  final libDir = Directory('${_resolvePublishedPackageRoot()}/lib');
  await libDir.create(recursive: true);

  final suffix = languageVersion.replaceAll('.', '_');

  _OutputFile dartFile(String pin, String variant, List<String> rules, {bool isPinnedSnapshot = false}) {
    final pinPart = pin.isEmpty ? '' : '_$pin';
    return _OutputFile(
      path: '${libDir.path}/dart_$variant$pinPart.yaml',
      rules: rules,
      pinning: isPinnedSnapshot ? 'pinned-to-language-$languageVersion' : 'unversioned-latest',
      variant: 'dart_$variant',
      isPinnedSnapshot: isPinnedSnapshot,
    );
  }

  _OutputFile flutterFile(String pin, String variant, List<String> rules, {bool isPinnedSnapshot = false}) {
    final pinPart = pin.isEmpty ? '' : '_$pin';
    return _OutputFile(
      path: '${libDir.path}/flutter_$variant$pinPart.yaml',
      rules: rules,
      pinning: isPinnedSnapshot ? 'pinned-to-language-$languageVersion' : 'unversioned-latest',
      variant: 'flutter_$variant',
      isPinnedSnapshot: isPinnedSnapshot,
      includesPackageFile: 'package:all_lints/dart_$variant$pinPart.yaml',
    );
  }

  final files = <_OutputFile>[
    dartFile('', 'stable', dartStable),
    dartFile(suffix, 'stable', dartStable, isPinnedSnapshot: true),
    dartFile('', 'all', dartAll),
    dartFile(suffix, 'all', dartAll, isPinnedSnapshot: true),
    flutterFile('', 'stable', flutterStable),
    flutterFile(suffix, 'stable', flutterStable, isPinnedSnapshot: true),
    flutterFile('', 'all', flutterAll),
    flutterFile(suffix, 'all', flutterAll, isPinnedSnapshot: true),
  ];

  for (final f in files) {
    final body = _renderFile(f, sdkVersion: sdkVersion, languageVersion: languageVersion);
    final existing = await _readIfExists(f.path);

    if (f.isPinnedSnapshot && existing != null && !overwritePinned) {
      final existingRules = _extractRuleListFromYaml(existing);
      if (existingRules != null && !_listsEqual(existingRules, f.rules)) {
        stderr
          ..writeln('REFUSING to overwrite frozen pinned file: ${f.path}')
          ..writeln('  Existing: ${existingRules.length} rules')
          ..writeln('  New:      ${f.rules.length} rules')
          ..writeln('  Diff:')
          ..writeln('    + only in new:      ${f.rules.toSet().difference(existingRules.toSet()).toList()..sort()}')
          ..writeln('    - only in existing: ${existingRules.toSet().difference(f.rules.toSet()).toList()..sort()}')
          ..writeln('Pass --overwrite-pinned to force.');
        return 2;
      }
    }
    await File(f.path).writeAsString(body);
    stderr.writeln('Wrote ${f.path} (${f.rules.length} rules)');
  }

  return 0;
}

class _Rule {
  _Rule(this.name, this.bucket, {this.isFlutter = false, this.exclusionReason = ''});
  final String name;
  final _Bucket bucket;
  final bool isFlutter;
  final String exclusionReason;
}

enum _Bucket { stable, experimental, excluded }

class _OutputFile {
  _OutputFile({
    required this.path,
    required this.rules,
    required this.pinning,
    required this.variant,
    this.isPinnedSnapshot = false,
    this.includesPackageFile,
  });
  final String path;
  final List<String> rules;
  final String pinning;
  final String variant;
  final bool isPinnedSnapshot;

  /// If non-null, the rendered YAML emits an `include: <this>` directive
  /// before its `linter.rules` block. Used to layer flutter_*.yaml on top
  /// of the matching dart_*.yaml.
  final String? includesPackageFile;
}

String _renderFile(_OutputFile f, {required String sdkVersion, required String languageVersion}) {
  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final buf = StringBuffer()
    ..writeln('# GENERATED FILE — do not edit by hand.')
    ..writeln('# Regenerate with: mise run generate')
    ..writeln('#')
    ..writeln('# Generated against:')
    ..writeln('#   Dart SDK version:      $sdkVersion')
    ..writeln('#   Dart language version: $languageVersion')
    ..writeln('# Generated on:            $today')
    ..writeln('# Variant:                 ${f.variant}')
    ..writeln(
      '# Rule count:              ${f.rules.length}${f.includesPackageFile == null ? '' : ' (additional, on top of include)'}',
    )
    ..writeln('# Pinning:                 ${f.pinning}')
    ..writeln('#')
    ..writeln('# Some rules in this list are mutually exclusive (e.g. prefer_single_quotes')
    ..writeln('# vs prefer_double_quotes). Disable the one you do not want in your own')
    ..writeln('# analysis_options.yaml — see the package README for the documented pairs.')
    ..writeln('#')
    ..writeln('# If your project pubspec sdk lower bound is below the language version above,')
    ..writeln('# some rules in this list may not fire on your code.')
    ..writeln();
  if (f.includesPackageFile != null) {
    buf
      ..writeln('include: ${f.includesPackageFile}')
      ..writeln();
  }
  buf
    ..writeln('linter:')
    ..writeln('  rules:');
  for (final rule in f.rules) {
    buf.writeln('    - $rule');
  }
  return buf.toString();
}

/// Flutter-specific rule names. Bootstrapped from SDK 3.11.2's `categories`
/// data and used as a fallback for older SDKs (3.2–3.5) where `rules.json`
/// did not yet populate the `categories` field. All twelve rules below are
/// present in every supported SDK; the only effect of this list is to flag
/// them as flutter-specific when the JSON lacks category metadata.
///
/// On every run, the generator cross-checks the JSON's category data against
/// this list and warns about drift.
const _knownFlutterRules = <String>{
  'avoid_unnecessary_containers',
  'avoid_web_libraries_in_flutter',
  'diagnostic_describe_all_properties',
  'no_logic_in_create_state',
  'sized_box_for_whitespace',
  'sized_box_shrink_expand',
  'sort_child_properties_last',
  'use_build_context_synchronously',
  'use_colored_box',
  'use_decorated_box',
  'use_full_hex_values_for_flutter_colors',
  'use_key_in_widget_constructors',
};

List<_Rule> _parseRules(String rulesJsonText) {
  final doc = jsonDecode(rulesJsonText);
  if (doc is! List) {
    throw StateError('rules.json: expected a top-level array');
  }

  // Detect drift between this run's JSON categories and the static fallback.
  final flutterFromJson = <String>{
    for (final entry in doc)
      if ((entry as Map)['categories'] is List && (entry['categories'] as List).contains('flutter'))
        entry['name'] as String,
  };
  if (flutterFromJson.isNotEmpty) {
    final missing = flutterFromJson.difference(_knownFlutterRules);
    final extra = _knownFlutterRules.difference(flutterFromJson);
    if (missing.isNotEmpty) {
      stderr.writeln(
        'WARN: rules.json tags these as flutter but they are not in the '
        'static fallback list — update _knownFlutterRules: $missing',
      );
    }
    if (extra.isNotEmpty) {
      stderr.writeln(
        'WARN: static fallback lists these as flutter but rules.json does '
        'not — they may have been removed or recategorized: $extra',
      );
    }
  }

  return doc.map((entry) {
    final m = entry as Map<String, dynamic>;
    final name = m['name'] as String;
    final cats = (m['categories'] as List?)?.cast<String>() ?? const <String>[];
    final isFlutter = cats.contains('flutter') || (cats.isEmpty && _knownFlutterRules.contains(name));
    return switch (m['state'] as String?) {
      'stable' => _Rule(name, _Bucket.stable, isFlutter: isFlutter),
      'experimental' => _Rule(name, _Bucket.experimental, isFlutter: isFlutter),
      'deprecated' => _Rule(name, _Bucket.excluded, isFlutter: isFlutter, exclusionReason: 'deprecated'),
      'removed' => _Rule(name, _Bucket.excluded, isFlutter: isFlutter, exclusionReason: 'removed'),
      final other => _Rule(name, _Bucket.excluded, isFlutter: isFlutter, exclusionReason: 'unknown:${other ?? 'null'}'),
    };
  }).toList();
}

String _currentSdkVersion() {
  final v = Platform.version;
  final match = RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(v);
  if (match == null) {
    throw StateError('Could not parse Platform.version: $v');
  }
  return match.group(1)!;
}

String _languageVersionOf(String sdkVersion) {
  final parts = sdkVersion.split('.');
  return '${parts[0]}.${parts[1]}';
}

String? _flagValue(List<String> args, String flag) {
  final prefix = '$flag=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  final i = args.indexOf(flag);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return null;
}

Future<String> _fetch(Uri uri) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('GET $uri returned ${res.statusCode}', uri: uri);
    }
    return res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<String?> _readIfExists(String path) async {
  final f = File(path);
  if (!await f.exists()) return null;
  return f.readAsString();
}

List<String>? _extractRuleListFromYaml(String text) {
  final doc = loadYaml(text);
  if (doc is! YamlMap) return null;
  final linter = doc['linter'];
  if (linter is! YamlMap) return null;
  final rules = linter['rules'];
  if (rules is! YamlList) return null;
  return rules.cast<String>().toList();
}

bool _listsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _resolvePublishedPackageRoot() {
  if (_publishedPackageRoot.isNotEmpty) return _publishedPackageRoot;
  // Script lives at packages/all_lints_generator/tool/generate.dart.
  // Output goes to the sibling all_lints package: ../../all_lints relative
  // to the script's parent (packages/all_lints_generator/).
  final scriptDir = File.fromUri(Platform.script).parent.path;
  return Directory('$scriptDir/../../all_lints').absolute.path;
}
