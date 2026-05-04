import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _wellKnownDartStableRules = ['avoid_print', 'prefer_const_constructors', 'unnecessary_this'];
const _wellKnownFlutterRules = ['use_key_in_widget_constructors', 'avoid_unnecessary_containers'];

/// Filename pattern: `(dart|flutter)_(stable|all)(_<major>_<minor>)?.yaml`.
final _filenamePattern = RegExp(r'^(dart|flutter)_(stable|all)(?:_(\d+)_(\d+))?\.yaml$');

void main() {
  // Generated YAMLs live in the sibling published package's lib/.
  final libDir = Directory('${Directory.current.path}/../all_lints/lib');
  final yamlFiles = libDir.listSync().whereType<File>().where((f) => f.path.endsWith('.yaml')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('lib/ contains generated YAML files', () {
    expect(yamlFiles, isNotEmpty, reason: 'run `mise run generate` first');
  });

  test('every YAML follows the dart_/flutter_ naming convention', () {
    for (final f in yamlFiles) {
      expect(_filenamePattern.hasMatch(_basename(f)), isTrue, reason: 'unexpected filename: ${_basename(f)}');
    }
  });

  for (final file in yamlFiles) {
    final base = _basename(file);
    final match = _filenamePattern.firstMatch(base)!;
    final prefix = match.group(1)!; // dart | flutter
    final variant = match.group(2)!; // stable | all
    final lang = match.group(3) == null ? null : '${match.group(3)}.${match.group(4)}';

    group('lib/$base', () {
      late String text;
      late YamlMap doc;

      setUpAll(() {
        text = file.readAsStringSync();
        doc = loadYaml(text) as YamlMap;
      });

      test('header records SDK version, language version, and pinning', () {
        expect(text, contains('Dart SDK version:'));
        expect(text, contains('Dart language version:'));
        expect(text, contains('Pinning:'));
      });

      if (lang != null) {
        test('header pinning matches filename suffix ($lang)', () {
          expect(text, contains('Pinning:                 pinned-to-language-$lang'));
          expect(text, contains('Dart language version: $lang'));
        });
      } else {
        test('unversioned file is marked as unversioned-latest', () {
          expect(text, contains('Pinning:                 unversioned-latest'));
        });
      }

      if (prefix == 'dart') {
        test('linter.rules > 100 entries, sorted, unique, no flutter rules', () {
          final rules = _readRules(file);
          expect(rules.length, greaterThan(100));
          final sorted = [...rules]..sort();
          expect(rules, equals(sorted), reason: 'hand-edits suspected — regenerate');
          expect(rules.toSet().length, rules.length, reason: 'duplicate rules');
          for (final r in _wellKnownDartStableRules) {
            expect(rules, contains(r));
          }
          for (final r in _wellKnownFlutterRules) {
            expect(rules, isNot(contains(r)), reason: '$r is flutter-specific; should be in flutter_*.yaml');
          }
        });

        test('no include directive', () {
          expect(doc['include'], isNull, reason: 'dart_*.yaml is meant to be a leaf, not include another package file');
        });
      } else {
        // flutter_*.yaml
        test('includes the matching dart_*.yaml', () {
          final pinPart = lang == null ? '' : '_${lang.replaceAll('.', '_')}';
          expect(doc['include'], equals('package:all_lints/dart_$variant$pinPart.yaml'));
        });

        test('linter.rules contains only flutter-specific rules, sorted, unique', () {
          final rules = _readRules(file);
          expect(rules, isNotEmpty);
          final sorted = [...rules]..sort();
          expect(rules, equals(sorted));
          expect(rules.toSet().length, rules.length);
          for (final r in _wellKnownFlutterRules) {
            expect(rules, contains(r));
          }
        });
      }
    });
  }

  test('stable is a subset of all (per prefix per suffix)', () {
    final groups = <(String, String?), ({List<String>? stable, List<String>? all})>{};
    for (final file in yamlFiles) {
      final m = _filenamePattern.firstMatch(_basename(file))!;
      final prefix = m.group(1)!;
      final variant = m.group(2)!;
      final lang = m.group(3) == null ? null : '${m.group(3)}.${m.group(4)}';
      final key = (prefix, lang);
      groups.putIfAbsent(key, () => (stable: null, all: null));
      final p = groups[key]!;
      groups[key] = (
        stable: variant == 'stable' ? _readRules(file) : p.stable,
        all: variant == 'all' ? _readRules(file) : p.all,
      );
    }
    for (final entry in groups.entries) {
      final stable = entry.value.stable;
      final all = entry.value.all;
      if (stable == null || all == null) continue;
      expect(stable.toSet().difference(all.toSet()), isEmpty, reason: 'stable rules missing from all (${entry.key})');
    }
  });

  test('unversioned files match the most recent suffixed files', () {
    for (final prefix in const ['dart', 'flutter']) {
      for (final variant in const ['stable', 'all']) {
        final unversioned = _findFile(yamlFiles, '${prefix}_$variant.yaml');
        final pinned = _findLatestSuffixed(yamlFiles, '${prefix}_$variant');
        if (unversioned != null && pinned != null) {
          expect(
            _readRules(unversioned),
            equals(_readRules(pinned)),
            reason: '${prefix}_$variant.yaml should equal latest pinned ${prefix}_${variant}_<lang>.yaml',
          );
        }
      }
    }
  });
}

String _basename(File f) => f.uri.pathSegments.last;

List<String> _readRules(File f) {
  final doc = loadYaml(f.readAsStringSync()) as YamlMap;
  final linter = doc['linter'];
  if (linter is! YamlMap) return const [];
  final rules = linter['rules'];
  if (rules is! YamlList) return const [];
  return rules.cast<String>().toList();
}

File? _findFile(List<File> files, String name) {
  for (final f in files) {
    if (f.uri.pathSegments.last == name) return f;
  }
  return null;
}

File? _findLatestSuffixed(List<File> files, String prefix) {
  final suffixed = <(int, int, File)>[];
  final pattern = RegExp('^${RegExp.escape(prefix)}_(\\d+)_(\\d+)\\.yaml\$');
  for (final f in files) {
    final m = pattern.firstMatch(f.uri.pathSegments.last);
    if (m != null) {
      suffixed.add((int.parse(m.group(1)!), int.parse(m.group(2)!), f));
    }
  }
  if (suffixed.isEmpty) return null;
  suffixed.sort((a, b) {
    if (a.$1 != b.$1) return b.$1.compareTo(a.$1);
    return b.$2.compareTo(a.$2);
  });
  return suffixed.first.$3;
}
