/// Checks that the plan's claims about what is done are still true.
///
///     dart run tool/verify_plan.dart
///     dart run tool/verify_plan.dart --all      also report unfinished items
///
/// **A status is a claim, and this is the only thing that checks it.** Twice in
/// one day a status carried forward from an older copy turned out to be wrong
/// in both directions: half of phase 0 was marked unfinished and was done, and
/// the dependency graph was missing fifty-two items because the parser that
/// built it dropped every identifier with two hyphens. Neither was caught by
/// anything, because nothing was looking.
///
/// **What it can check, and what it cannot.** An acceptance clause is a
/// sentence in Russian — "the shading there will be wrong", "a person who typed
/// 0.07 asked for 0.07" — and no tool reads those. What every row *does* carry
/// is names in backticks: types, functions, files. Those are mechanical, and
/// they are what rots. So the invariant here is narrow and true:
///
///   **everything a finished item names must exist.**
///
/// A finished item that names `ProjectWriter` and has no `ProjectWriter` is
/// either not finished or has drifted since it was, and both are worth a red
/// line. An unfinished item naming something absent is the ordinary case and is
/// silent unless `--all` asks.
///
/// **It does not say an item is done.** It says a claim of done is not
/// contradicted by the source — which is a weaker thing than a test and a
/// stronger thing than a memory. The acceptance column stays the contract;
/// this is the part of it a machine can hold.
library;

import 'dart:convert';
import 'dart:io';

/// One item of §2.
final class PlanItem {
  const PlanItem({
    required this.id,
    required this.what,
    required this.acceptance,
    required this.line,
  });

  final String id;
  final String what;
  final String acceptance;

  /// Where it is in the plan, so a complaint can be opened.
  final int line;

  /// Everything the row names in backticks, deduplicated.
  Set<String> get named => _backticked
      .allMatches('$what $acceptance')
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}

final RegExp _backticked = RegExp(r'`([^`]+)`');
final RegExp _escape = RegExp(r'\\[nrt]');
// A trailing `-n` or `-d` beyond the digit run — the two suffixes the plan's
// own intro names, "-n" for a row added by critique and "-d" for one added
// by an owner decision — sometimes glued straight onto the digits
// (`mat-09n`, already matched by the trailing `[a-z]*` alone) and sometimes
// its own dash-separated letter on a row that already had a letter suffix
// of its own (`doc-11a-n`, `mat-04a-n`, `anim-31a-n`), which the single
// trailing `[a-z]*` cannot also cover since it has already been spent on
// the "a". Deliberately `[nd]` and not `[a-z]+`: several rows carry a
// *descriptive* dash-slug after their number instead (`view-01-bench`,
// `view-02-viewport-skeleton`), which `plan-status.json` keys by the bare
// number alone — a wider trailing group would fold that slug into the id
// and break every one of those rows the same way this one was broken.
final RegExp _rowId = RegExp(
  r'^`?([a-z][a-z0-9]*(?:-[a-z]+)?-[0-9]+[a-z]*(?:-[nd])?)`?',
);

/// A Dart identifier worth looking for: a type, a member or a function.
///
/// **Deliberately narrow.** The rows are full of backticked prose — flag names,
/// file extensions, whole expressions, English words used as terms of art — and
/// a checker that looked for all of them would report a hundred absences a run
/// and be switched off in a week. What is taken is what a `grep` can answer
/// without ambiguity: a bare identifier, optionally with one dotted member or a
/// pair of parentheses.
final RegExp _identifier = RegExp(
  r'^([A-Za-z_][A-Za-z0-9_]*)(\.[A-Za-z0-9_]+)?(\(\))?$',
);

/// Words that look like identifiers and are not ours.
///
/// Every one of these appeared as a false absence on the first run. They are
/// listed rather than filtered by a pattern because a pattern wide enough to
/// catch them all would also catch real names.
const Set<String> _notOurs = <String>{
  // Ordinary words the rows use as terms.
  'says', 'name', 'kind', 'mode', 'level', 'axis', 'step', 'width', 'height',
  'radius', 'segments', 'rings', 'shape', 'size', 'count', 'index', 'version',
  'profile', 'target', 'parent', 'id', 'ids', 'to', 'by', 'at', 'from',
  'true', 'false', 'null', 'int', 'double', 'bool', 'String', 'List', 'Map',
  'Set', 'Future', 'void', 'dynamic', 'Object', 'Iterable', 'Widget',
  // Tools and files outside this repository.
  'dart', 'flutter', 'git', 'npx', 'python3', 'godot', 'bash', 'curl',
};

void main(List<String> arguments) {
  final all = arguments.contains('--all');
  final root = Directory.current;

  final items = _readPlan(File('doc/model-editor-plan.md'));
  if (items.isEmpty) {
    stderr.writeln('no items parsed out of doc/model-editor-plan.md');
    exit(2);
  }

  final statuses = _readStatuses(File('doc/plan-status.json'));
  final excused = _readExcuses(File('doc/plan-status.json'));
  final (:Set<String> declared, :Set<String> mentioned) = _namesIn(root);

  final unknownIds =
      statuses.keys
          .where((String id) => !items.any((PlanItem i) => i.id == id))
          .toList()
        ..sort();

  var checked = 0;
  var broken = 0;
  final complaints = <String>[];
  final borrowed = <String>[];
  final stale = <String>[];

  for (final PlanItem item in items) {
    final String status = statuses[item.id] ?? 'todo';
    if (!all && status != 'done') continue;

    final excuses = excused[item.id] ?? const <String, String>{};
    final missing = <String>[];
    final elsewhere = <String>[];
    for (final String named in item.named) {
      final String? symbol = _asSymbol(named);
      if (symbol == null) continue;
      final bool here = declared.contains(symbol);
      if (excuses.containsKey(symbol)) {
        // An excuse says a name is deliberately not in the tree. When the name
        // turns up, the excuse is the thing that has gone stale, and leaving it
        // would blind the check to that name for good.
        if (here) stale.add('  ${item.id} no longer needs `$symbol`');
        continue;
      }
      if (here) continue;
      (mentioned.contains(symbol) ? elsewhere : missing).add(named);
    }
    checked++;
    if (elsewhere.isNotEmpty) {
      borrowed.add(
        '  ${item.id} (${item.line}) uses '
        '${elsewhere.map((String m) => '`$m`').join(', ')}',
      );
    }
    if (missing.isEmpty) continue;
    broken++;
    complaints.add(
      '  ${item.id} (${item.line}, $status) names '
      '${missing.map((String m) => '`$m`').join(', ')}',
    );
  }

  stdout.writeln(
    '${items.length} items, $checked checked, ${declared.length} names '
    'declared and ${mentioned.length} named at all in the tree',
  );

  if (unknownIds.isNotEmpty) {
    stdout
      ..writeln()
      ..writeln('✗ a status names an item the plan does not have')
      ..writeln('  ${unknownIds.join(', ')}');
  }
  if (complaints.isNotEmpty) {
    stdout
      ..writeln()
      ..writeln('✗ a finished item names something that is not there')
      ..writeln(complaints.join('\n'));
  }
  if (all && borrowed.isNotEmpty) {
    stdout
      ..writeln()
      ..writeln(
        '· named in the tree but declared elsewhere — SDK, a '
        'dependency, a format keyword',
      )
      ..writeln(borrowed.join('\n'));
  }

  if (stale.isNotEmpty) {
    stdout
      ..writeln()
      ..writeln('✗ an excuse in doc/plan-status.json is out of date')
      ..writeln(stale.join('\n'));
  }

  if (unknownIds.isEmpty && broken == 0 && stale.isEmpty) {
    stdout.writeln('\n✓ everything the finished items name is there');
    exit(0);
  }
  exit(1);
}

/// The rows of §2, in order.
List<PlanItem> _readPlan(File plan) {
  final lines = plan.readAsLinesSync();
  final items = <PlanItem>[];
  var inside = false;
  for (var i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (line.startsWith('## 2. ')) inside = true;
    // §3.3 adds items too — three names that resolved to none of §2's rows
    // and were given their own. A status naming one of them was "unknown"
    // until this widened, which hid syn-01/02/03 from every check below.
    if (line.startsWith('### 3.3 ')) inside = true;
    if (line.startsWith('## 3. ')) inside = false;
    if (line.startsWith('## 4. ')) break;
    if (!inside || !line.startsWith('| ')) continue;
    final cells = line.trim().split('|').map((String c) => c.trim()).toList();
    // A leading and a trailing empty cell from the pipes at both ends.
    if (cells.length != 9) continue;
    final match = _rowId.firstMatch(cells[1]);
    if (match == null) continue;
    items.add(
      PlanItem(
        id: match.group(1)!,
        what: cells[2],
        acceptance: cells[7],
        line: i + 1,
      ),
    );
  }
  return items;
}

Map<String, String> _readStatuses(File file) {
  if (!file.existsSync()) return const <String, String>{};
  final body = jsonDecode(file.readAsStringSync());
  if (body case {'status': final Map<String, dynamic> status}) {
    return status.map((String k, dynamic v) => MapEntry(k, '$v'));
  }
  return const <String, String>{};
}

/// Names a finished item may go on saying while the tree does not have them,
/// each with the reason, by item id.
///
/// **An exception without a reason is a hole in the check.** These are the
/// three shapes that turn up honestly: a word that exists to be rejected, a
/// prototype the row itself puts in another branch, and a name the row says
/// belongs to a later phase. Anything else is drift wearing an excuse.
Map<String, Map<String, String>> _readExcuses(File file) {
  if (!file.existsSync()) return const <String, Map<String, String>>{};
  final body = jsonDecode(file.readAsStringSync());
  if (body case {'absent': final Map<String, dynamic> absent}) {
    return absent.map(
      (String id, dynamic names) => MapEntry(id, <String, String>{
        for (final MapEntry<String, dynamic> e
            in (names as Map<String, dynamic>).entries)
          e.key: '${e.value}',
      }),
    );
  }
  return const <String, Map<String, String>>{};
}

/// [named] as a symbol worth looking for, or null when it is prose.
String? _asSymbol(String named) {
  final String trimmed = named.trim();
  if (trimmed.endsWith('.dart') || trimmed.contains('/')) return null;
  final match = _identifier.firstMatch(trimmed);
  if (match == null) return null;
  final String head = match.group(1)!;
  // A dotted member is looked up by its head: `ModelObject.version` is present
  // if `ModelObject` is, because a field of a class this file cannot parse is
  // not a thing a regular expression should be asked about.
  if (_notOurs.contains(head)) return null;
  if (head.length < 3) return null;
  return head;
}

/// Two answers to "is this name in the tree", because there are two ways for a
/// name to be there and only one of them is a claim about our own code.
///
/// `declared` is what our source declares: a class, a function, a field. A
/// finished row naming something that is *not* declared here has either not
/// been written or has been renamed.
///
/// `mentioned` is every word that appears anywhere under the code roots. That
/// covers the whole other half of what the rows name — `SegmentedButton`,
/// `kIsWeb`, `Ticker` come from Flutter; `map_Kd` is a keyword of a file
/// format; `material_symbols_icons` is a line in a pubspec. None of those are
/// ours to declare, and all of them are visible in the tree at the place they
/// are used, which is exactly what makes the row's claim checkable.
///
/// A name in neither is the red line. **Nothing outside the tree is consulted**
/// — no analyser, no SDK, no pub cache — so the whole check is a `grep` and
/// costs a second.
({Set<String> declared, Set<String> mentioned}) _namesIn(Directory root) {
  final declared = <String>{};
  final mentioned = <String>{};
  final declaration = RegExp(
    r'\b(?:class|mixin|enum|extension|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)'
    r'|\b([A-Za-z_][A-Za-z0-9_]*)\s*\('
    r'|\b(?:final|const|var|late)\s+(?:[A-Za-z_][A-Za-z0-9_<>,?\s]*\s+)?'
    r'([A-Za-z_][A-Za-z0-9_]*)\s*[=;]'
    r'|\bget\s+([A-Za-z_][A-Za-z0-9_]*)',
  );
  final word = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');
  for (final String where in <String>['packages', 'apps', 'tool', '.github']) {
    final directory = Directory('${root.path}/$where');
    if (!directory.existsSync()) continue;
    for (final FileSystemEntity entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      final String path = entity.path;
      if (path.contains('/.dart_tool/') || path.contains('/build/')) continue;
      if (!_readable.any(path.endsWith)) continue;
      final String body = entity.readAsStringSync();
      // `\n` inside a quoted string is a newline, and a tokenizer that does not
      // know it reads `\ndependency_overrides` as one word starting with `n` —
      // which is how a name that is in a file got reported as absent from it.
      mentioned.addAll(
        word
            .allMatches(body.replaceAll(_escape, ' '))
            .map((RegExpMatch m) => m.group(0)!),
      );
      // The file's own name without its extension, so a row naming a file is
      // answered by the file being there.
      final String name = entity.uri.pathSegments.last;
      mentioned.add(name);
      mentioned.add(name.split('.').first);
      if (!path.endsWith('.dart')) continue;
      declared.add(name.replaceAll('.dart', ''));
      for (final RegExpMatch match in declaration.allMatches(body)) {
        for (var group = 1; group <= 4; group++) {
          final String? found = match.group(group);
          if (found != null) declared.add(found);
        }
      }
    }
  }
  return (declared: declared, mentioned: mentioned);
}

/// Files worth reading for names. Everything else in the tree is a picture, a
/// mesh or a compiled thing, and a word found inside one of those would be an
/// accident.
const List<String> _readable = <String>[
  '.dart',
  '.yaml',
  '.yml',
  '.sh',
  '.plist',
  '.json',
  '.xcconfig',
  '.pbxproj',
  '.gradle',
  '.kt',
  '.swift',
  '.h',
  '.m',
  '.cc',
  '.html',
  '.js',
  '.css',
  '.glsl',
  '.frag',
  '.vert',
  '.txt',
  '.xml',
  '.entitlements',
  '.obj',
  '.mtl',
];
