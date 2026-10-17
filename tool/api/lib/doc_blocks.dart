/// The Dart blocks of the documentation, read so the analyzer can resolve
/// them: `bin/doc_blocks.dart` writes each into a file of its own with the
/// imports its page shows, analyzes them all, and reads back what resolves
/// wrong.
///
/// **A rename leaves its old spelling on the site.** `migrate` and
/// `dart fix` reach a user's code and never the pages that taught it, so
/// every rename of the 1.0 work left `Material(...)`, `GameLoop(...)` and
/// `CpuDevice.readPixels` in front of a reader, compiling nowhere.
///
/// **What counts.** Only names that resolve wrong: an undefined class,
/// function, member or parameter, a missing required argument, an argument
/// of the wrong type. A variable an earlier block of the page made is not a
/// finding, nor a type the page declares; a name of the engine's API is.
/// Syntax is not read: a block that elides with `...` still has its names
/// resolved.
///
/// **A fragment says so.** A block that is deliberately not code a reader
/// can paste — a signature table, an excerpt in the middle of a method —
/// opens with ` ```dart fragment `, which the site and GitHub render as
/// Dart. Nothing else is skipped.
library;

import 'package:analyzer/dart/analysis/utilities.dart';

/// One fenced Dart block of a page.
final class DocBlock {
  DocBlock({
    required this.line,
    required this.source,
    required this.imports,
    required this.fragment,
  });

  /// The page's line number of the block's first line of code.
  final int line;

  /// The block's code with its import directives taken out, each replaced
  /// by an empty line so the lines still count from [line].
  final String source;

  /// The import directives it is read with: its own, the ones an earlier
  /// block of the page showed, and the page's fallback (the packages it
  /// lists under `dependencies:`, or the ones it is about).
  final List<String> imports;

  /// Whether the fence says ` ```dart fragment `.
  final bool fragment;
}

/// A block written out, and where: the page it came from and the number of
/// lines the file has before the block's first line.
typedef DocSnippet = ({DocBlock block, String doc, int offset});

/// One name that resolves wrong, at its page's line.
final class DocFinding {
  DocFinding(this.doc, this.line, this.code, this.message);

  final String doc;
  final int line;
  final String code;
  final String message;

  @override
  String toString() => '$doc:$line: $message ($code)';
}

final RegExp _fence = RegExp(
  r'^```dart([^\n]*)\n(.*?)^```',
  multiLine: true,
  dotAll: true,
);
final RegExp _import = RegExp(
  r"^[ \t]*import\s+'[^']+'[^;]*;[ \t]*(?://[^\n]*)?$",
  multiLine: true,
);

/// Every Dart block of [text], with the imports each is read with: its
/// own, those an earlier block showed, and [fallback], which a reader of the
/// page has added already.
List<DocBlock> docBlocksOf(String text, {required List<String> fallback}) {
  final out = <DocBlock>[];
  var shown = <String>[];
  for (final m in _fence.allMatches(text)) {
    final info = m.group(1)!.trim().split(RegExp(r'\s+'));
    final body = m.group(2)!;
    final own = <String>[
      for (final i in _import.allMatches(body))
        i.group(0)!.trim().replaceAll(RegExp(r'\s+'), ' '),
    ];
    if (own.isNotEmpty) {
      shown = <String>{...shown, ...own}.toList()..sort();
    }
    out.add(
      DocBlock(
        line: '\n'.allMatches(text.substring(0, m.start)).length + 2,
        source: body.replaceAllMapped(
          _import,
          (Match i) => '\n' * '\n'.allMatches(i.group(0)!).length,
        ),
        imports: <String>{...shown, ...fallback}.toList()..sort(),
        fragment: info.contains('fragment'),
      ),
    );
  }
  return out;
}

/// The packages a ` ```yaml ` block of [text] lists under `dependencies:`,
/// in the order it lists them.
List<String> declaredDependencies(String text) {
  final out = <String>[];
  for (final m in RegExp(
    r'^```yaml\n(.*?)^```',
    multiLine: true,
    dotAll: true,
  ).allMatches(text)) {
    final yaml = m.group(1)!;
    final start = RegExp(
      r'^dependencies:\s*$',
      multiLine: true,
    ).firstMatch(yaml);
    if (start == null) continue;
    for (final line in yaml.substring(start.end).split('\n').skip(1)) {
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      if (!line.startsWith(' ')) break;
      final name = RegExp(r'^  ([a-z_][a-z0-9_]*):').firstMatch(line);
      if (name != null) out.add(name.group(1)!);
    }
  }
  return out;
}

/// [block] as a file: its imports, then its code as top-level code, as the
/// body of a function or as the body of a class, whichever parses with the
/// fewest syntax errors (top-level first on a tie).
({String source, int offset}) snippetFor(DocBlock block) {
  final head =
      '${block.imports.join('\n')}\n'
      '// ignore_for_file: type=lint, unused_import, unused_local_variable\n';
  final lines = '\n'.allMatches(head).length;
  final variants = <({String source, int offset})>[
    (source: '$head${block.source}', offset: lines),
    (
      source: '${head}Future<void> _snippet() async {\n${block.source}\n}\n',
      offset: lines + 1,
    ),
    (
      source: '${head}abstract class _Snippet {\n${block.source}\n}\n',
      offset: lines + 1,
    ),
  ];
  int errors(String source) =>
      parseString(content: source, throwIfDiagnostics: false).errors.length;
  var best = variants.first;
  var fewest = errors(best.source);
  for (final variant in variants.skip(1)) {
    final count = errors(variant.source);
    if (count < fewest) {
      best = variant;
      fewest = count;
    }
  }
  return best;
}

/// The analyzer's codes for a name that resolves wrong.
const Set<String> resolutionCodes = <String>{
  'ABSTRACT_CLASS_INSTANTIATION',
  'AMBIGUOUS_IMPORT',
  'ARGUMENT_TYPE_NOT_ASSIGNABLE',
  'CREATION_WITH_NON_TYPE',
  'EXTRA_POSITIONAL_ARGUMENTS',
  'EXTRA_POSITIONAL_ARGUMENTS_COULD_BE_NAMED',
  'FINAL_CLASS_EXTENDED_OUTSIDE_OF_LIBRARY',
  'FINAL_CLASS_IMPLEMENTED_OUTSIDE_OF_LIBRARY',
  'BASE_CLASS_IMPLEMENTED_OUTSIDE_OF_LIBRARY',
  'INSTANTIATE_ABSTRACT_CLASS',
  'INTERFACE_CLASS_EXTENDED_OUTSIDE_OF_LIBRARY',
  'INVALID_OVERRIDE',
  'INVALID_USE_OF_INTERNAL_MEMBER',
  'INVALID_USE_OF_VISIBLE_FOR_TESTING_MEMBER',
  'MISSING_REQUIRED_ARGUMENT',
  'NEW_WITH_UNDEFINED_CONSTRUCTOR',
  'NEW_WITH_UNDEFINED_CONSTRUCTOR_DEFAULT',
  'NON_ABSTRACT_CLASS_INHERITS_ABSTRACT_MEMBER',
  'NON_TYPE_AS_TYPE_ARGUMENT',
  'NON_TYPE_IN_CATCH_CLAUSE',
  'NOT_A_TYPE',
  'NOT_ENOUGH_POSITIONAL_ARGUMENTS',
  'SUBTYPE_OF_FINAL_IS_NOT_BASE_FINAL_OR_SEALED',
  'UNDEFINED_CLASS',
  'UNDEFINED_CONSTRUCTOR_IN_INITIALIZER',
  'UNDEFINED_ENUM_CONSTANT',
  'UNDEFINED_EXTENSION_GETTER',
  'UNDEFINED_EXTENSION_METHOD',
  'UNDEFINED_FUNCTION',
  'UNDEFINED_GETTER',
  'UNDEFINED_IDENTIFIER',
  'UNDEFINED_METHOD',
  'UNDEFINED_NAMED_PARAMETER',
  'UNDEFINED_OPERATOR',
  'UNDEFINED_PREFIXED_NAME',
  'UNDEFINED_SETTER',
  'UNDEFINED_SUPER_MEMBER',
  'URI_DOES_NOT_EXIST',
};

/// The types each page's blocks declare, by page: `class`, `enum`, `mixin`,
/// `typedef` and `extension type` names.
Set<String> typesDeclaredIn(Iterable<DocBlock> blocks) => <String>{
  for (final block in blocks)
    for (final m in RegExp(
      r'\b(?:class|enum|mixin|typedef|extension\s+type)\s+([A-Z][\w$]*)',
    ).allMatches(block.source))
      m.group(1)!,
};

/// What resolves wrong in [machineOutput] (`dart analyze --format=machine`)
/// over the files of [files], at each page's line.
///
/// [apiFunctions] is every lowercase top-level name the published snapshots
/// declare: an undefined lowercase name is a variable of the page unless it
/// is one of those. [pageTypes] is [typesDeclaredIn] each page.
List<DocFinding> findingsIn(
  String machineOutput,
  Map<String, DocSnippet> files, {
  required Set<String> apiFunctions,
  required Map<String, Set<String>> pageTypes,
}) {
  final out = <DocFinding>[];
  for (final row in machineOutput.split('\n')) {
    final parts = row.split('|');
    if (parts.length < 8) continue;
    final code = parts[2];
    final snippet = files[parts[3]];
    if (snippet == null || !resolutionCodes.contains(code)) continue;
    final message = parts.sublist(7).join('|');
    final name = RegExp("'([^']+)'").firstMatch(message)?.group(1) ?? '';
    final undefinedName = const <String>{
      'UNDEFINED_IDENTIFIER',
      'UNDEFINED_FUNCTION',
      'UNDEFINED_CLASS',
      'NOT_A_TYPE',
      'CREATION_WITH_NON_TYPE',
      'NON_TYPE_AS_TYPE_ARGUMENT',
      'NON_TYPE_IN_CATCH_CLAUSE',
    }.contains(code);
    if (undefinedName) {
      final lower = name.isNotEmpty && name[0] == name[0].toLowerCase();
      // A variable an earlier block of the page made.
      if (lower && !apiFunctions.contains(name)) continue;
      // A type the page declares in a block of its own.
      if (!lower &&
          (pageTypes[snippet.doc] ?? const <String>{}).contains(name)) {
        continue;
      }
    }
    // A member of the page's own class, called from a block written as that
    // class's body.
    if (message.contains("for the type '_Snippet'")) continue;
    out.add(
      DocFinding(
        snippet.doc,
        snippet.block.line + int.parse(parts[4]) - (snippet.offset + 1),
        code,
        message,
      ),
    );
  }
  return out;
}
