/// The generated half of the site's migration guide: every entry of the
/// tables, grouped by package, each under the anchor the diagnostics and
/// the TODO comments link to.
library;

import 'dart:math' as math;

import 'lints_table.dart' show internalAnchor, toNamedOf;
import 'table.dart';

/// The markers the generated part sits between in the guide's Markdown.
const String guideStart = '<!-- migration-table:start -->';

/// The marker that closes the generated part, after [guideStart].
const String guideEnd = '<!-- migration-table:end -->';

/// How an entry is carried out, in the guide's words.
String howCarriedOut(MigrationEntry e) => switch (e.kind) {
  // A positional argument that became named is written by `migrate`: `dart
  // fix` has the change in `fix_data.yaml` and offers no fix for the extra
  // positional argument a call is left with.
  'parameters' when toNamedOf(e).isNotEmpty => '`migrate`',
  'rename' || 'moved' || 'parameters' => '`dart fix`',
  'rewrite' ||
  'implementsToWith' ||
  'import' ||
  'regroup' ||
  'recordToClass' ||
  'argument' ||
  'hookContext' => '`migrate`',
  'subclassModifier' when e.to == 'base' => '`migrate`',
  // Nothing outside a final class's package may subclass it: what it leaves
  // is a TODO at each clause that did.
  'subclassModifier' => '`migrate`, with a TODO',
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
    '`${e.symbol}${e.template!.contains('{arguments}') ? '(…)' : ''}` becomes '
        '`${e.template!.replaceAll(RegExp(r'\s+'), ' ').replaceAll('{target}', 'x').replaceAll('{arguments}', '…').replaceAll('{typeArguments}', 'T').trim()}`.',
  'implementsToWith' =>
    '`${e.topName}` is a base mixin class: `implements ${e.topName}` '
        'becomes `with ${e.topName}`, on a `base` class.',
  'subclassModifier' when e.to == 'base' =>
    '`${e.topName}` is a `base` class: a class below it is `base` itself, '
        'and `implements ${e.topName}` becomes `extends ${e.topName}`.',
  'subclassModifier' =>
    '`${e.topName}` is a `final` class: a class that extended or '
        'implemented it gets a TODO.',
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
  'argument' => _argument(e),
  'parameters' when toNamedOf(e).isNotEmpty => _toNamed(e),
  'hookContext' => _hookContext(e),
  _ => '',
};

/// A `hookContext` entry in the guide's words: what an override takes now,
/// and where each of its old parameters is read from.
String _hookContext(MigrationEntry e) {
  final context = e.fields['context'];
  if (e.fieldMap.isEmpty) {
    return '`${e.symbol}` takes one `$context` where it took nothing: an '
        'override takes it, and a call hands one asking for nothing, '
        '`const $context()`.';
  }
  final reads = <String>[
    for (final MapEntry(:key, :value) in e.fieldMap.entries)
      int.tryParse(key) == null
          ? '`$key:` is `.$value`'
          : 'parameter ${int.parse(key) + 1} is `.$value`',
  ].join(', ');
  return '`${e.symbol}` takes one `$context`: an override '
      'reads its old parameters from it ($reads), and a call builds one.';
}

/// A `parameters` entry's positional arguments that became named, in the
/// guide's words: `Gauge(r, 2)` is `Gauge(r, scale: 2)`.
String _toNamed(MigrationEntry e) {
  final callable = e.member == e.topName ? e.topName : e.symbol;
  final named = toNamedOf(e);
  final last = named.keys.map(int.parse).reduce(math.max);
  final before = <String>[for (var i = 0; i <= last; i++) 'x$i'];
  final after = <String>[
    for (final (i, x) in before.indexed)
      if (named['$i'] case final name?) '$name: $x' else x,
  ];
  return '`$callable(${before.join(', ')})` is '
      '`$callable(${after.join(', ')})`.';
}

/// An `argument` entry in the guide's words: the value as it was passed,
/// and as it is passed now, with `x` for the value (or its components).
String _argument(MigrationEntry e) {
  final type = e.types.firstOrNull;
  final parts = switch (type) {
    'Vector2' => 'x, y',
    'Vector3' => 'x, y, z',
    'Vector4' => 'x, y, z, w',
    _ => 'x',
  };
  final value = type == null ? 'x' : '$type($parts)';
  final written = e.template == null
      ? value
      : e.template!
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll('{components}', parts)
            .replaceAll('{value}', value)
            .trim();
  if (e.arguments case [final only]) {
    return '`$only: $value` of `${e.symbol}` is `${e.to ?? only}: $written`.';
  }
  return '${e.arguments.map((String a) => '`$a:`').join(', ')} of '
      '`${e.symbol}`: `$value` is `$written`.';
}

/// The Markdown between [guideStart] and [guideEnd]: every table, newest
/// first, since a reader on the last candidate wants the last table.
String generateGuideTable(List<MigrationTable> tables) {
  final out = StringBuffer()..writeln(guideStart);
  for (final table in MigrationTable.chain(tables).reversed) {
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
        '${table.toName}, ${counts['by hand'] ?? 0} by hand: '
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
        out.writeln(_internalRow(package, internal, table.toName));
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

/// [page] with its generated part, between [startMarker] and [endMarker],
/// replaced by [table]; null when the page has no markers.
String? spliceGuide(
  String page,
  String table, {
  String startMarker = guideStart,
  String endMarker = guideEnd,
}) {
  final start = page.indexOf(startMarker);
  final end = page.indexOf(endMarker);
  if (start < 0 || end < start) return null;
  return page.substring(0, start) +
      table +
      page.substring(end + endMarker.length);
}
