/// The generated half of the site's migration guide: every entry of the
/// tables, grouped by package, each under the anchor the diagnostics and
/// the TODO comments link to.
library;

import 'table.dart';

/// The markers the generated part sits between in the guide's Markdown.
const String guideStart = '<!-- migration-table:start -->';
const String guideEnd = '<!-- migration-table:end -->';

/// How an entry is carried out, in the guide's words.
String howCarriedOut(MigrationEntry e) => switch (e.kind) {
  'rename' || 'moved' || 'parameters' => '`dart fix`',
  'rewrite' || 'implementsToWith' => '`migrate`',
  'import' => '`migrate`',
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
        '${table.to}: '
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
      for (final e in entries) {
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
