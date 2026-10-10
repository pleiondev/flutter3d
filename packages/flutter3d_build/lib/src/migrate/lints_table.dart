/// `flutter3d_lints/lib/src/migration/table.g.dart`, written from the
/// migration tables: the entries the analyzer plugin and `dart run
/// flutter3d_lints:migrate` check a resolved project against — `rewrite`,
/// `implementsToWith`, `regroup`, `enumToClass`, `recordToClass`,
/// `nullToThrow`, `internal` and `manual`.
///
/// The plugin cannot read this package's YAML (it does not depend on it, and
/// the analysis server runs it apart from any project), so the table is
/// compiled into it as constants. [lintsRules] is the same table as data,
/// which the batch migrator also takes as JSON (`--rules`), so a test can
/// run a table of its own through it.
library;

import 'table.dart';

/// Which uses a manual entry is about, when the entry does not say:
/// a new case of a sealed type or a new enum value breaks `switch`es; a
/// change only an implementer feels breaks the `implements` clauses; the
/// rest breaks every use.
({String match, String? switchOver}) inferMatch(MigrationEntry e) {
  final explicit = e.fields['match'] as String?;
  final over = RegExp(
    r'^`(\w+)` has (?:a new case|new values|a new value)',
  ).firstMatch(e.text)?.group(1);
  if (explicit != null) return (match: explicit, switchOver: over);
  if (over != null) return (match: 'switches', switchOver: over);
  if (RegExp(
    r'Only (code that implements|a backend of your own|an encoder of your own)',
  ).hasMatch(e.text)) {
    return (match: 'subtypes', switchOver: null);
  }
  return (match: 'uses', switchOver: null);
}

/// The first sentence of [text]: what a diagnostic says.
String firstSentence(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  var inCode = false;
  for (var i = 0; i < flat.length - 1; i++) {
    if (flat[i] == '`') inCode = !inCode;
    if (!inCode && flat[i] == '.' && flat[i + 1] == ' ') {
      return flat.substring(0, i + 1);
    }
  }
  return flat;
}

/// The kinds the plugin carries, each as its `MigrationKind`.
const Set<String> lintsKinds = <String>{
  'rewrite',
  'implementsToWith',
  'regroup',
  'enumToClass',
  'recordToClass',
  'nullToThrow',
  'internal',
  'manual',
};

/// The anchor of [package]'s one line of `internal` names in the guide.
String internalAnchor(String package) => 'internal-$package';

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// What a diagnostic for [e] says, from [table].
String _message(MigrationEntry e, MigrationTable table) {
  final callable = e.member ?? e.topName;
  return switch (e.kind) {
    'implementsToWith' =>
      '`${e.topName}` is a base mixin class in ${table.to}: a class mixes it '
          'in with `with` and is `base`, `final` or `sealed` itself.',
    'rewrite' when e.text.isEmpty =>
      '`${e.symbol}` is deprecated in ${table.to}; the fix asks the same '
          'receiver `${_flat(e.template!).replaceAll('{target}.', '').replaceAll('{target}', 'it').replaceAll('{0}', '…')}` '
          'instead.',
    'internal' =>
      '`${e.symbol}` was ${e.package}\'s own and is not exported since '
          '${table.to}.',
    'regroup' when e.text.isEmpty =>
      '`${e.arguments.join('`, `')}` of `$callable` moved into '
          '`${e.into}: ${e.options}(…)` in ${table.to}.',
    'enumToClass' when e.text.isEmpty =>
      '`${e.topName}` is not an enum or a sealed type in ${table.to}: a '
          '`switch` over it needs a case for the values added later.',
    'recordToClass' when e.text.isEmpty =>
      '`${e.topName}` is a class in ${table.to}, not a record: '
          '${e.fieldMap.entries.map((MapEntry<String, String> f) => '`.${f.key}` is `.${f.value}`').join(', ')}.',
    'nullToThrow' when e.text.isEmpty =>
      '`$callable` throws `${e.exception}` in ${table.to} where it returned '
          'null.',
    _ => firstSentence(e.text),
  };
}

/// Every rule of the plugin's table, from [tables], as plain data: the
/// fields of a `MigrationRule`, without the ones at their default.
List<Map<String, Object?>> lintsRules(List<MigrationTable> tables) =>
    <Map<String, Object?>>[
      for (final table in tables)
        for (final e in table.entries)
          if (lintsKinds.contains(e.kind)) _rule(e, table),
    ];

Map<String, Object?> _rule(MigrationEntry e, MigrationTable table) {
  final (:match, :switchOver) = e.kind == 'manual'
      ? inferMatch(e)
      : (match: 'uses', switchOver: e.kind == 'enumToClass' ? e.topName : null);
  final members = <String>[
    if (e.kind == 'regroup')
      ...e.arguments
    else
      for (final m in (e.fields['members'] as List<Object?>?) ?? const []) '$m',
  ];
  final isLibrary = e.symbol.contains(':');
  return <String, Object?>{
    'id': e.id,
    'kind': e.kind,
    'package': e.package,
    'type': e.kind == 'recordToClass' ? (e.to ?? e.topName) : e.topName,
    'member': ?e.member,
    if (e.template != null) 'template': _flat(e.template!),
    if (e.imports.isNotEmpty) 'imports': e.imports,
    'switchOver': ?switchOver,
    if (match != 'uses') 'match': match,
    if (members.isNotEmpty) 'members': members,
    'into': ?e.into,
    'options': ?e.options,
    if (e.kind == 'recordToClass') 'fields': e.fieldMap,
    'exception': ?e.exception,
    if (e.kind == 'internal' && e.instead != null) 'instead': _flat(e.instead!),
    if (e.kind == 'internal' && isLibrary) 'library': true,
    'message': _message(e, table),
    'link': e.kind == 'internal'
        ? '${table.guide}#${internalAnchor(e.package)}'
        : table.linkFor(e),
  };
}

String _string(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

String _strings(List<String> list) =>
    '<String>[${list.map(_string).join(', ')}]';

/// The Dart source of the plugin's table, from [tables].
String generateLintsTable(
  List<MigrationTable> tables, {
  required String stamp,
}) {
  final out = StringBuffer()
    ..writeln(
      '// GENERATED by `dart run tool/generate_migrations.dart` in '
      'flutter3d_build, from',
    )
    ..writeln('// flutter3d_build/lib/migrations/*.yaml. Do not edit.')
    ..writeln('// table-stamp: $stamp')
    ..writeln()
    ..writeln("import 'migration_rule.dart';")
    ..writeln()
    ..writeln(
      '/// Every migration the plugin and the batch migrator check a '
      'resolved',
    )
    ..writeln('/// project against.')
    ..writeln('const List<MigrationRule> migrationRules = <MigrationRule>[');
  for (final rule in lintsRules(tables)) {
    out.writeln('  MigrationRule(');
    for (final MapEntry(:key, :value) in rule.entries) {
      final text = switch ((key, value)) {
        ('kind', final String kind) => 'MigrationKind.$kind',
        ('match', final String match) => 'MigrationMatch.$match',
        (_, final bool flag) => '$flag',
        (_, final String s) => _string(s),
        (_, final List<String> list) => _strings(list),
        (_, final Map<String, String> map) =>
          '<String, String>{${map.entries.map((MapEntry<String, String> f) => '${_string(f.key)}: ${_string(f.value)}').join(', ')}}',
        _ => throw StateError('$key: $value'),
      };
      out.writeln('    $key: $text,');
    }
    out.writeln('  ),');
  }
  out.writeln('];');
  return out.toString();
}
