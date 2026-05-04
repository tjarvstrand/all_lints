/// Prepares a patch release of the `all_lints` package against a target Dart
/// SDK version (latest stable by default).
///
/// What it does, in order:
///
/// 1. Resolves the target SDK (from `--target=X.Y.Z` or the latest stable
///    GitHub release of `dart-lang/sdk`).
/// 2. If `packages/all_lints/lib/dart_all_X_Y.yaml` already exists for the
///    target's language version, prints `skipped=true` and exits 0. (Pinned
///    files are frozen; if we have one for this language version, the
///    unversioned files were written in the same prior run — nothing to do.)
/// 3. Runs `tool/generate.dart --sdk-version=X.Y.Z`.
/// 4. Refuses to continue if `## [Unreleased]` in the published package's
///    CHANGELOG has any pending entries (exits 1 with a clear message).
/// 5. Bumps the published `pubspec.yaml` patch version.
/// 6. Inserts a `## [X.Y.Z] - YYYY-MM-DD` section into the CHANGELOG with a
///    "Regenerated against Dart SDK X.Y.Z" note.
///
/// What it does NOT do: git operations. The caller (CI workflow or maintainer)
/// is responsible for committing, tagging, and pushing.
///
/// Stdout (machine-parseable):
///   `skipped=true`               — when there is nothing to do
///   `new_version=<X.Y.Z>`        — when a release was prepared
///   `target_sdk=<X.Y.Z>`         — when a release was prepared
///
/// Test locally:
///   mise run release:prepare --target=3.11.4
///   git diff packages/all_lints
///   git restore packages/all_lints   # to undo
library;

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final target = _flagValue(args, '--target') ?? await _fetchLatestStableDartSdk();
  final lang = _languageVersionOf(target);
  final suffix = lang.replaceAll('.', '_');
  final dryPrefix = dryRun ? '[DRY RUN] ' : '';

  final publishedRoot = _resolvePublishedPackageRoot();
  final pinnedFile = File('$publishedRoot/lib/dart_all_$suffix.yaml');
  if (pinnedFile.existsSync()) {
    stderr.writeln('Pinned files for language $lang already exist (${pinnedFile.path}); nothing to do.');
    stdout.writeln('skipped=true');
    if (dryRun) stdout.writeln('dry_run=true');
    return 0;
  }

  final generatorRoot = _resolveGeneratorPackageRoot();
  stderr.writeln('${dryPrefix}Regenerating against Dart SDK $target (language $lang)...');
  if (!dryRun) {
    final result = await Process.start(
      'dart',
      ['run', 'tool/generate.dart', '--sdk-version=$target', '--language-version=$lang'],
      workingDirectory: generatorRoot,
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await result.exitCode;
    if (code != 0) return code;
  } else {
    stderr.writeln('  (would run: dart run tool/generate.dart --sdk-version=$target --language-version=$lang)');
  }

  final changelogPath = '$publishedRoot/CHANGELOG.md';
  final changelog = File(changelogPath).readAsStringSync();
  final pendingUnreleased = _extractUnreleasedBody(changelog);
  if (pendingUnreleased.isNotEmpty) {
    stderr
      ..writeln('Pending [Unreleased] CHANGELOG entries; refusing to release.')
      ..writeln('Resolve them (move into a versioned section) and rerun.')
      ..writeln()
      ..writeln('Pending entries:')
      ..writeln(pendingUnreleased);
    return 1;
  }

  final pubspecPath = '$publishedRoot/pubspec.yaml';
  final pubspec = File(pubspecPath).readAsStringSync();
  final versionPattern = RegExp(r'^version:\s+(\d+)\.(\d+)\.(\d+)\s*$', multiLine: true);
  final m = versionPattern.firstMatch(pubspec);
  if (m == null) {
    stderr.writeln('Could not parse version from $pubspecPath');
    return 1;
  }
  final maj = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final pat = int.parse(m.group(3)!);
  final newVersion = '$maj.$min.${pat + 1}';

  final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final entry = '## [$newVersion] - $today\n\n### Changed\n\n- Regenerated against Dart SDK $target.\n\n';

  if (!dryRun) {
    File(pubspecPath).writeAsStringSync(pubspec.replaceFirst(versionPattern, 'version: $newVersion'));
    final updated = changelog.replaceFirst(
      RegExp(r'^## \[Unreleased\]\n\n', multiLine: true),
      '## [Unreleased]\n\n$entry',
    );
    File(changelogPath).writeAsStringSync(updated);
  } else {
    stderr
      ..writeln('  (would bump $pubspecPath: version $maj.$min.$pat → $newVersion)')
      ..writeln('  (would prepend to $changelogPath: $entry)');
  }

  stderr.writeln('${dryPrefix}Prepared release v$newVersion for Dart SDK $target.');
  stdout
    ..writeln('new_version=$newVersion')
    ..writeln('target_sdk=$target');
  if (dryRun) stdout.writeln('dry_run=true');
  return 0;
}

String _resolveGeneratorPackageRoot() {
  // Script lives at packages/all_lints_generator/tool/release.dart, so the
  // generator package root is one level up from the script's parent.
  final scriptDir = File.fromUri(Platform.script).parent.path;
  return Directory(scriptDir).parent.absolute.path;
}

String _resolvePublishedPackageRoot() {
  return Directory('${_resolveGeneratorPackageRoot()}/../all_lints').absolute.path;
}

/// The Dart team doesn't publish GitHub Releases for `dart-lang/sdk` — only
/// git tags — so `/repos/dart-lang/sdk/releases/latest` 404s. Use the
/// official Dart archive endpoint, which is what `dart upgrade` and other
/// tooling reads.
Future<String> _fetchLatestStableDartSdk() async {
  final uri = Uri.https('storage.googleapis.com', '/dart-archive/channels/stable/release/latest/VERSION');
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('GET $uri returned ${res.statusCode}', uri: uri);
    }
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['version'] as String;
  } finally {
    client.close();
  }
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

/// Returns the meaningful body lines under `## [Unreleased]` — content the
/// caller hasn't yet released. Filters out blank lines, `###` subsection
/// headings, and reference-style link definitions like `[Unreleased]: <url>`.
String _extractUnreleasedBody(String changelog) {
  final body = <String>[];
  var inUnreleased = false;
  for (final line in changelog.split('\n')) {
    if (line.startsWith('## [Unreleased]')) {
      inUnreleased = true;
      continue;
    }
    if (inUnreleased && line.startsWith('## [')) break;
    if (!inUnreleased) continue;
    if (line.trim().isEmpty) continue;
    if (line.startsWith('### ')) continue;
    if (RegExp(r'^\[.+\]: ').hasMatch(line)) continue;
    body.add(line);
  }
  return body.join('\n');
}
