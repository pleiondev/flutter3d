/// The generated half of the site's migration guide: every entry of the
/// tables, grouped by package, each under the anchor the diagnostics and
/// the TODO comments link to.
library;

import 'lints_table.dart' show internalAnchor;
import 'table.dart';

/// The markers the generated part sits between in the guide's Markdown.
const String guideStart = '<!-- migration-table:start -->';
const String guideEnd = '<!-- migration-table:end -->';

/// How an entry is carried out, in the guide's words.
String howCarriedOut(MigrationEntry e) => switch (e.kind) {
  'rename' || 'moved' || 'parameters' => '`dart fix`',
  'rewrite' || 'implementsToWith' || 'import' => '`migrate`',
  'regroup' || 'recordToClass' => '`migrate`',
  // Each leaves a TODO beside what it wrote: a throw where a value used to
  // fall through, a `try` around what used to answer null.
  'enumToClass' || 'nullToThrow' => '`migrate`, with a TODO',
  'internal' => 'gone internal',
  'none' => 'nothing to do',
  _ => 'by hand',
};

String _what(MigrationEntry e, MigrationTable table) => switch (e.kind) {
  'rename' => '`${e.symbol}` is `${e.to}`.',
  'moved' when e.symbol.contains(':') =>
    'Names re-exported from `${e.symbol}` are imported from `${e.to}`.',
  'moved' => '`${e.symbol}` is imported from `${e.to}`.',
  'rewrite' =>
    '`${e.symbol}` becomes '
        '`${e.template!.replaceAll(RegExp(r'\s+'), ' ').replaceAll('{target}', 'x').trim()}`.',
  'implementsToWith' =>
    '`${e.topName}` is a base mixin class: `implements ${e.topName}` '
        'becomes `with ${e.topName}`, on a `base` class.',
  'import' => '`${e.from}` is `${e.to}`.',
  'regroup' =>
    '`${e.arguments.map((String a) => '$a:').join(' ')}` of `${e.symbol}` '
        'go inside `${e.into}: ${e.options}(…)`.',
  'enumToClass' =>
    '`${e.topName}` is a class: a `switch` over it that names every value '
        'gains `_ => throw UnimplementedError()`.',
  'recordToClass' =>
    '`${e.topName}` is a class: '
        '${e.fieldMap.entries.map((MapEntry<String, String> f) => '`.${f.key}` is `.${f.value}`').join(', ')}; '
        'a destructuring pattern is yours to rewrite.',
  'nullToThrow' =>
    '`${e.symbol}` throws `${e.exception}` where it returned null: a null '
        'check beside a call becomes `try … on ${e.exception}`.',
  _ => '',
};

/// The Markdown between [guideStart] and [guideEnd].
String generateGuideTable(List<MigrationTable> tables) {
  final out = StringBuffer()..writeln(guideStart);
  for (final table in tables) {
    final byPackage = <String, List<MigrationEntry>>{};
    for (final e in table.entries) {
      final package = e.kind == 'import'
          ? RegExp(r'^package:(\w+)/').firstMatch(e.from ?? '')?.group(1) ?? ''
          : e.package;
      (byPackage[package] ??= <MigrationEntry>[]).add(e);
    }
    final counts = <String, int>{};
    for (final e in table.entries) {
      final how = howCarriedOut(e);
      counts[how] = (counts[how] ?? 0) + 1;
    }
    out
      ..writeln()
      ..writeln(
        '*Generated from `flutter3d_build/lib/migrations/` — '
        '${table.entries.length} entries from ${table.from} to '
        '${table.to}, ${counts['by hand'] ?? 0} by hand: '
        '${counts.entries.map((MapEntry<String, int> c) => '${c.value} ${c.key}').join(', ')}.*',
      );
    for (final package in byPackage.keys.toList()..sort()) {
      out
        ..writeln()
        ..writeln('### `$package`')
        ..writeln();
      final entries = byPackage[package]!
        ..sort(
          (MigrationEntry a, MigrationEntry b) => a.symbol.compareTo(b.symbol),
        );
      final internal = <MigrationEntry>[
        for (final e in entries)
          if (e.kind == 'internal') e,
      ];
      if (internal.isNotEmpty) {
        out.writeln(_internalRow(package, internal, table.to));
      }
      for (final e in entries) {
        if (e.kind == 'internal') continue;
        final what = _what(e, table);
        final text = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        out.writeln(
          '- <a id="${e.id}"></a>**${e.kind == 'import' ? '`${e.from}`' : '`${e.symbol}`'}** '
          '(${howCarriedOut(e)}). '
          '${<String>[what, text].where((String s) => s.isNotEmpty).join(' ')}',
        );
      }
    }
  }
  out
    ..writeln()
    ..write(guideEnd);
  return out.toString();
}

/// The one line for [package]'s `internal` [entries]: how many, each name
/// under its own anchor (so an entry's id still finds it), and what stays
/// public instead, once per distinct word.
String _internalRow(String package, List<MigrationEntry> entries, String to) {
  final names = <String>[
    for (final e in entries) '<a id="${e.id}"></a>`${e.symbol}`',
  ];
  final instead = <String>{
    for (final e in entries)
      if (e.instead case final i?) i.replaceAll(RegExp(r'\s+'), ' ').trim(),
  };
  final count = entries.length;
  return '- <a id="${internalAnchor(package)}"></a>**$count '
      '${count == 1 ? 'name was' : 'names were'} the package\'s own** '
      '(gone internal): they are not exported since $to, and the import of '
      '`$package` that brought them gets one diagnostic for all of them. '
      '${names.join(', ')}.'
      '${instead.map((String i) => ' $i').join()}';
}

/// [page] with its generated part replaced by [table]; null when the page
/// has no markers.
String? spliceGuide(String page, String table) {
  final start = page.indexOf(guideStart);
  final end = page.indexOf(guideEnd);
  if (start < 0 || end < start) return null;
  return page.substring(0, start) +
      table +
      page.substring(end + guideEnd.length);
}
