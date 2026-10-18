import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'migration/migration_scan.dart' show ownedPackage;

/// What a project's imports of the engine get wrong, found in one
/// compilation unit.
///
/// **Two questions, both about directives and names, so both answer on an
/// unresolved unit.** Whether a library is the engine's internal one is in
/// its URI; whether two `Matrix4`s meet in a file is in its imports and in
/// the names it writes. A resolver adds nothing to either, which is why a
/// test can hand in `parseString`'s result and get the answer the analysis
/// server gets.
///
/// [ownPackage] is the name of the package the unit belongs to, or null when
/// it is not known. A unit inside one of the engine's own packages
/// ([ownedPackage]) reaches whatever the repository's structure rules let
/// it: their `restrictedLibraryUsers` table decides, not this scan.
List<ImportFinding> scanEngineImports(
  CompilationUnit unit, {
  String? ownPackage,
}) {
  final found = <ImportFinding>[];
  final inside = ownPackage != null && ownedPackage(ownPackage);
  final directives = unit.directives.whereType<NamespaceDirective>();
  if (!inside) {
    for (final directive in directives) {
      final uri = directive.uri.stringValue;
      if (uri == null || !isEngineInternalUri(uri)) continue;
      found.add(
        ImportFinding(
          rule: EngineImportRules.internalImports,
          offset: directive.uri.offset,
          length: directive.uri.length,
          what: uri,
        ),
      );
    }
  }
  final imports = unit.directives.whereType<ImportDirective>().toList();
  final engine = imports.where(
    (ImportDirective d) =>
        engineMatrix4Libraries.contains(d.uri.stringValue) && _bringsMatrix4(d),
  );
  if (engine.isEmpty || !_writesMatrix4(unit)) return found;
  for (final directive in imports) {
    if (!flutterMatrix4Libraries.contains(directive.uri.stringValue)) continue;
    if (!_bringsMatrix4(directive)) continue;
    found.add(
      ImportFinding(
        rule: EngineImportRules.flutterMatrix4,
        offset: directive.uri.offset,
        length: directive.uri.length,
        what: directive.uri.stringValue!,
        edit: _hideMatrix4(directive),
      ),
    );
  }
  return found;
}

/// One import a project should not have written as it did.
final class ImportFinding {
  /// A finding of [rule] over the source range [offset]…[offset] + [length],
  /// with the library it is about in [what], and the edit that resolves it
  /// when there is one.
  const ImportFinding({
    required this.rule,
    required this.offset,
    required this.length,
    required this.what,
    this.edit,
  });

  /// The rule's name: one of [EngineImportRules.all].
  final String rule;

  /// Offset of the import's URI string in the unit's source, in UTF-16 code
  /// units.
  final int offset;

  /// Length of the URI string, quotes included, in UTF-16 code units.
  final int length;

  /// The URI the directive names, as written.
  final String what;

  /// The quick fix as one replacement in the unit's source, or null when
  /// the rule has none ([EngineImportRules.internalImports]: what to import
  /// instead is the author's decision).
  final ImportEdit? edit;

  @override
  String toString() => '$rule at $offset: $what';
}

/// An insertion into a unit's source: [text] at [offset].
final class ImportEdit {
  /// [text] written at [offset], replacing nothing.
  const ImportEdit(this.offset, this.text);

  /// Where [text] goes, in UTF-16 code units from the start of the unit.
  final int offset;

  /// What is inserted: `' hide Matrix4'` or `', Matrix4'`.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ImportEdit && other.offset == offset && other.text == text;

  @override
  int get hashCode => Object.hash(offset, text);

  @override
  String toString() => 'at $offset insert "$text"';
}

/// The names of the import rules, which are also their diagnostic codes.
abstract final class EngineImportRules {
  /// An import or export of an engine package's `internal.dart`,
  /// `builtin.dart` or `src/` from outside the engine's packages.
  static const String internalImports = 'avoid_engine_internal_imports';

  /// Flutter's `Matrix4` and the engine's meeting in one file, with neither
  /// hidden.
  static const String flutterMatrix4 = 'hide_flutter_matrix4';

  /// Every rule, in the order they are registered.
  static const List<String> all = <String>[internalImports, flutterMatrix4];
}

/// Whether [uri] is a library of an engine package that is outside semver:
/// its `internal.dart` or `builtin.dart`, which the engine's packages share
/// within one minor, or anything under its `src/`, which is no library of
/// the package at all.
///
/// A `testing.dart` is not here: a game's tests are what it is for.
bool isEngineInternalUri(String uri) {
  final match = RegExp(r'^package:(\w+)/(.+)$').firstMatch(uri);
  if (match == null || !ownedPackage(match.group(1)!)) return false;
  final path = match.group(2)!;
  return path == 'internal.dart' ||
      path == 'builtin.dart' ||
      path.startsWith('src/');
}

/// The Flutter libraries that export `vector_math_64`'s `Matrix4`:
/// `widgets.dart` and `rendering.dart` export it, and `material.dart` and
/// `cupertino.dart` export `widgets.dart`.
const Set<String> flutterMatrix4Libraries = <String>{
  'package:flutter/widgets.dart',
  'package:flutter/material.dart',
  'package:flutter/cupertino.dart',
  'package:flutter/rendering.dart',
};

/// The libraries that export the `Matrix4` the engine's signatures take,
/// `vector_math`'s single-precision one. `test/import_scan_test.dart` reads
/// the facade's export to keep this list true.
const Set<String> engineMatrix4Libraries = <String>{
  'package:vector_math/vector_math.dart',
  'package:flutter3d/flutter3d.dart',
};

/// Whether [directive] lets an unprefixed `Matrix4` into the unit: no
/// prefix, no `hide Matrix4`, and no `show` list that leaves it out.
bool _bringsMatrix4(ImportDirective directive) {
  if (directive.prefix != null) return false;
  for (final combinator in directive.combinators) {
    final names = switch (combinator) {
      ShowCombinator(:final shownNames) => shownNames,
      HideCombinator(:final hiddenNames) => hiddenNames,
    };
    final named = names.any((SimpleIdentifier n) => n.name == 'Matrix4');
    if (combinator is ShowCombinator && !named) return false;
    if (combinator is HideCombinator && named) return false;
  }
  return true;
}

/// Whether the unit names `Matrix4` without a prefix anywhere: a type, a
/// constructor, a static call.
bool _writesMatrix4(CompilationUnit unit) {
  final finder = _Matrix4Finder();
  unit.accept(finder);
  return finder.found;
}

/// The edit that hides `Matrix4` from [directive]: appended to its `hide`
/// list when it has one, a new `hide` before the semicolon otherwise.
ImportEdit _hideMatrix4(ImportDirective directive) {
  for (final combinator in directive.combinators) {
    if (combinator is HideCombinator) {
      return ImportEdit(combinator.end, ', Matrix4');
    }
  }
  return ImportEdit(directive.semicolon.offset, ' hide Matrix4');
}

final class _Matrix4Finder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitNamedType(NamedType node) {
    if (node.importPrefix == null && node.name.lexeme == 'Matrix4') {
      found = true;
    }
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'Matrix4' &&
        node.parent is! Combinator &&
        node.parent is! PrefixedIdentifier) {
      found = true;
    }
    super.visitSimpleIdentifier(node);
  }
}
