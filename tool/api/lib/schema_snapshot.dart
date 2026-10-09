/// The tools a package offers an agent, as text: what `api/<package>.mcp`
/// and `api/<package>.vm` hold.
///
/// **Two surfaces nothing compiles against.** An MCP tool is called by a name
/// in somebody's host config and by arguments a model read out of its schema;
/// a VM service extension is called by a name in an editor attached to a
/// running game, with string parameters. A rename or a new required argument
/// breaks every one of those callers, and nothing in this repository fails
/// when it happens, because the callers are not here. Decision 11 of
/// `tasks/1.0-stability.md` puts both under the same semver as the Dart API,
/// and these snapshots are how a change to them becomes a version decision —
/// `tool/structure/schema.dart` classifies it.
///
/// **What `.mcp` lists**, for every server class in the package (a subclass of
/// `flutter3d_mcp`'s `ToolTableServer`): the name the server announces,
/// its schema version and aliases, and for each tool its name, the first
/// sentence of its description, what it does to the world (`hints`, and
/// `writes` for an edit that is none of read-only, destructive, idempotent
/// or open-world), its
/// input schema — one line per argument, with `required` where it is, keys
/// sorted, and every `description` and `title` taken out, since prose moves
/// nothing a call may send — and the output schema of the
/// `structuredContent` it answers with, on an `out` line.
///
/// **A plugin's tools** are snapshotted the same way by
/// `--plugin package:<package>#<Plugin>`: the plugin installed into an engine
/// with an empty `McpTools`, and what it added written to the plugin
/// package's own `api/<package>.plugin.mcp`, one `server` block per namespace with the schema
/// version it declared.
///
/// **How the tools are read.** A server in a plain Dart package is built, here
/// in this process, and its own `tools` list read back: whatever a server
/// does to its tools on the way in (the modeller widens every command that
/// acts on a selection) is in the snapshot because it is in the server.
/// A server in a package that needs Flutter cannot be built under `dart run`,
/// so its tool list is read from the source instead — each `mcpTool(...)` in the
/// list its constructor passes as `tools:`, with the top-level helpers those
/// expressions name, copied into a small program that does run under
/// `dart run` and prints them. A tool list that is anything but a list of
/// `X(mcpTool(...), handler)` — written out, returned by a top-level helper, or
/// either under an `if` with no `else` — is refused by name rather than half
/// read.
///
/// **A tool offered to some hosts only** (`sim_mcp`'s `order`, there only
/// when the session's game is an `OrderedGame`) is in the snapshot with a
/// `when` line naming the condition. The list is built for a probe that is
/// every kind of game the tools ask about, so each guarded tool shows up with
/// its schema, and the `when` line keeps a reader from taking it for one
/// every host gets. Making an unconditional tool conditional is a break for
/// the hosts that lose it; `tool/structure/schema.dart` says so.
///
/// **What `.vm` lists**: every `registerExtension` and
/// `registerFlutter3dExtension` name in the package's `lib/` with the
/// parameter keys its handler reads — followed into the functions it hands
/// `parameters` to — each with the type the handler parses it as, then a
/// `->` line with the keys of the JSON object it answers — the `answers:`
/// it declares when it declares them, read off the handler's `jsonEncode`
/// otherwise — and an `alias` line for each old name it keeps; and every
/// `postToolEvent` kind, as `flutter3d.<kind>`. Read from the source, parsed
/// and not run: these packages need Flutter.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Where a package's MCP snapshot lives, relative to the package.
String mcpSnapshotPathOf(String package) => 'api/$package.mcp';

/// Where a package's VM service snapshot lives, relative to the package.
String vmSnapshotPathOf(String package) => 'api/$package.vm';

/// One server's surface, as plain JSON values: `name`, `schemaVersion`,
/// `aliases` (old name to current) and `tools` (each `ToolSpec` as its
/// JSON, with `_meta`'s `flutter3d/when` for a tool offered to some hosts).
typedef ServerSurface = Map<String, Object?>;

/// One extension: the parameters its handler reads, each to the type it
/// parses the string as (`int`, `double`, `bool`, `json` or `string`), the
/// keys of the JSON object it answers with — `*` among them when part of the
/// answer is built where the snapshot cannot read it and the registration
/// declares no `answers:` — and the old names it keeps as `aliases:`.
typedef VmExtension = ({
  Map<String, String> parameters,
  Set<String> result,
  List<String> aliases,
});

/// What a game's VM service offers: each extension by name, and the event
/// kinds it posts.
typedef VmSurface = ({Map<String, VmExtension> extensions, Set<String> events});

/// What every kind `postToolEvent` posts is prefixed with on the VM service
/// — `flutter3d_game`'s `toolEventPrefix`.
const String gameEventPrefix = 'flutter3d.';

/// The `_meta` key a tool offered to some hosts only carries its condition
/// under, in the program that reads a server's tools from source.
const String whenMetaKey = 'flutter3d/when';

// ------------------------------------------------------------------ files

/// Every `.dart` file under [package]'s `lib/`, sorted.
List<File> libraryFiles(Directory package) {
  final lib = Directory('${package.path}/lib');
  if (!lib.existsSync()) return const <File>[];
  return lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

/// Whether [package] depends on the Flutter SDK, and so cannot be built
/// under `dart run`.
bool needsFlutter(Directory package) => RegExp(
  r'^\s+flutter:\s*\n\s+sdk:\s*flutter',
  multiLine: true,
).hasMatch(File('${package.path}/pubspec.yaml').readAsStringSync());

/// The names of the classes in [package] that extend `ToolTableServer`.
List<String> serverClassesIn(Directory package) => <String>[
  for (final file in libraryFiles(package))
    if (file.readAsStringSync().contains('ToolTableServer'))
      for (final c in parseString(
        content: file.readAsStringSync(),
        throwIfDiagnostics: false,
      ).unit.declarations.whereType<ClassDeclaration>())
        if (c.extendsClause?.superclass.name.lexeme == 'ToolTableServer')
          c.namePart.typeName.lexeme,
]..sort();

// -------------------------------------------------------------- rendering

/// [servers] as `api/<package>.mcp` holds them.
String renderMcp(String package, List<ServerSurface> servers) {
  final out = StringBuffer()
    ..writeln('# The MCP tools of $package: what each server offers an agent.')
    ..writeln(
      '# Generated by `dart run api_snapshot:schema_snapshot --update '
      '$package` in tool/api. Do not edit.',
    )
    ..writeln(
      '# A change here is a semver decision: see "Tools for agents are a '
      'contract too" in CONTRIBUTING.md.',
    );
  final sorted = <ServerSurface>[...servers]
    ..sort(
      (ServerSurface a, ServerSurface b) =>
          (a['name']! as String).compareTo(b['name']! as String),
    );
  for (final server in sorted) {
    out
      ..writeln()
      ..writeln('server ${server['name']}');
    if (server['schemaVersion'] case final String v) {
      out.writeln('  schema $v');
    }
    final aliases = (server['aliases'] as Map? ?? const <String, String>{})
        .cast<String, String>();
    for (final old in aliases.keys.toList()..sort()) {
      out.writeln('  alias $old -> ${aliases[old]}');
    }
    final tools =
        <Map<String, Object?>>[
          for (final t in server['tools']! as List)
            (t as Map).cast<String, Object?>(),
        ]..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              (a['name']! as String).compareTo(b['name']! as String),
        );
    for (final tool in tools) {
      out
        ..writeln()
        ..write(_renderTool(tool));
    }
  }
  return out.toString();
}

String _renderTool(Map<String, Object?> tool) {
  final out = StringBuffer()..writeln('tool ${tool['name']}');
  final says = firstSentence(tool['description'] as String? ?? '');
  if (says.isNotEmpty) out.writeln('  says $says');
  final meta = (tool['_meta'] as Map? ?? const <String, Object?>{})
      .cast<String, Object?>();
  if (tool['when'] ?? meta[whenMetaKey] case final String condition) {
    out.writeln('  when $condition');
  }
  final hints = (tool['annotations'] as Map? ?? const <String, Object?>{})
      .cast<String, Object?>();
  final said = <String>[
    if (hints['readOnlyHint'] == true) 'readOnly',
    if (hints['destructiveHint'] == true) 'destructive',
    if (hints['idempotentHint'] == true) 'idempotent',
    if (hints['openWorldHint'] == true) 'openWorld',
  ];
  // Every tool says what it does: an ordinary edit, none of the four hints,
  // is written `writes` rather than left out, so a tool nobody classified
  // reads differently from one that was.
  out.writeln('  hints ${said.isEmpty ? 'writes' : said.join(' ')}');
  final input = normaliseSchema(
    (tool['inputSchema'] as Map? ?? const <String, Object?>{})
        .cast<String, Object?>(),
  );
  final properties = (input['properties'] as Map? ?? const <String, Object?>{})
      .cast<String, Object?>();
  final required = <Object?>{...?input['required'] as List?};
  for (final name in properties.keys.toList()..sort()) {
    if (name.isEmpty || name.contains(RegExp(r'\s'))) {
      throw StateError(
        'the tool ${tool['name']} has an argument named "$name", which a '
        'snapshot line cannot hold',
      );
    }
    out.writeln(
      '  arg $name ${required.contains(name) ? 'required ' : ''}'
      '${jsonEncode(properties[name])}',
    );
  }
  final rest = <String, Object?>{
    for (final e in input.entries)
      if (e.key != 'properties' &&
          e.key != 'required' &&
          !(e.key == 'type' && e.value == 'object'))
        e.key: e.value,
  };
  if (rest.isNotEmpty) out.writeln('  schema ${jsonEncode(rest)}');
  if (tool['outputSchema'] case final Map<Object?, Object?> output) {
    out.writeln(
      '  out ${jsonEncode(normaliseSchema(output.cast<String, Object?>()))}',
    );
  }
  return out.toString();
}

/// The first sentence of [text]: up to the first full stop that ends a
/// sentence, on its first line.
///
/// Only the first, because the rest of a description is advice to a model —
/// worth rewording whenever it helps, and no business of a version number.
/// The first sentence is what the tool is, and a reader of a diff should see
/// it move.
String firstSentence(String text) {
  final line = text.split('\n').first.trim();
  final end = RegExp(r'[.!?](?=\s|$)').firstMatch(line);
  return end == null ? line : line.substring(0, end.end);
}

/// [schema] with every `description` and `title` taken out and every map's
/// keys sorted — a property *named* `description` stays.
Map<String, Object?> normaliseSchema(Map<String, Object?> schema) {
  Object? value(String key, Object? v) => switch (key) {
    'properties' || r'$defs' || 'definitions' => <String, Object?>{
      for (final name in ((v! as Map).keys.cast<String>().toList()..sort()))
        name: normaliseSchema(
          ((v as Map)[name] as Map).cast<String, Object?>(),
        ),
    },
    'items' ||
    'additionalProperties' ||
    'not' ||
    'contains' when v is Map => normaliseSchema(v.cast<String, Object?>()),
    // Which fields are required is a set; the order they were written in
    // is nothing a call depends on.
    'required' when v is List => <String>[for (final n in v) '$n']..sort(),
    'anyOf' || 'oneOf' || 'allOf' when v is List => <Object?>[
      for (final s in v) normaliseSchema((s as Map).cast<String, Object?>()),
    ],
    _ => _sorted(v),
  };
  return <String, Object?>{
    for (final key in schema.keys.toList()..sort())
      if (key != 'description' && key != 'title') key: value(key, schema[key]),
  };
}

Object? _sorted(Object? v) => switch (v) {
  final Map<Object?, Object?> m => <String, Object?>{
    for (final k in (m.keys.map((Object? k) => '$k').toList()..sort()))
      k: _sorted(m[k]),
  },
  final List<Object?> l => <Object?>[for (final x in l) _sorted(x)],
  _ => v,
};

/// [surface] as `api/<package>.vm` holds it.
String renderVm(String package, VmSurface surface) {
  final out = StringBuffer()
    ..writeln(
      '# The VM service surface of $package: the extensions a tool attached '
      'to a running game calls, and the events it hears.',
    )
    ..writeln(
      '# Generated by `dart run api_snapshot:schema_snapshot --update '
      '$package` in tool/api. Do not edit.',
    )
    ..writeln(
      '# A change here is a semver decision: see "Tools for agents are a '
      'contract too" in CONTRIBUTING.md.',
    );
  for (final name in surface.extensions.keys.toList()..sort()) {
    out
      ..writeln()
      ..writeln('extension $name');
    final extension = surface.extensions[name]!;
    for (final alias in extension.aliases.toList()..sort()) {
      out.writeln('  alias $alias');
    }
    for (final key in extension.parameters.keys.toList()..sort()) {
      out.writeln('  $key ${extension.parameters[key]}');
    }
    if (extension.result.isNotEmpty) {
      out.writeln('  -> ${(extension.result.toList()..sort()).join(' ')}');
    }
  }
  for (final name in surface.events.toList()..sort()) {
    out
      ..writeln()
      ..writeln('event $name');
  }
  return out.toString();
}

// ----------------------------------------------------------- the VM scan

/// The extensions [package] registers and the events it posts, read from
/// its `lib/`.
///
/// Parameter keys are the string literals a handler indexes its parameter
/// map with — `parameters['step']` — followed into every top-level function
/// of the package the map is handed to, and into the function a local
/// helper is given for it (`flutter3d_app`'s render extensions are one local
/// `answer('passes', ask: renderPasses)` per verb). A name that is built
/// some other way is refused rather than guessed.
VmSurface scanVm(Directory package) {
  final units = <String, CompilationUnit>{};
  for (final file in libraryFiles(package)) {
    final text = file.readAsStringSync();
    if (!text.contains('registerExtension') &&
        !text.contains('registerFlutter3dExtension') &&
        !text.contains('postToolEvent') &&
        !text.contains('postEvent')) {
      // Still parsed when a handler hands its parameters to a function in
      // here, below — but only then.
      continue;
    }
    units[file.path] = parseString(
      content: text,
      throwIfDiagnostics: false,
    ).unit;
  }
  final functions = _TopLevelFunctions(package);
  final extensions = <String, VmExtension>{};
  final events = <String>{};
  for (final entry in units.entries) {
    entry.value.accept(_VmVisitor(entry.key, functions, extensions, events));
  }
  return (extensions: extensions, events: events);
}

/// Every top-level function of a package, by name, parsed on first use.
final class _TopLevelFunctions {
  _TopLevelFunctions(this.package);
  final Directory package;
  Map<String, FunctionDeclaration>? _all;

  FunctionDeclaration? operator [](String name) {
    final all = _all ??= <String, FunctionDeclaration>{
      for (final file in libraryFiles(package))
        for (final f in parseString(
          content: file.readAsStringSync(),
          throwIfDiagnostics: false,
        ).unit.declarations.whereType<FunctionDeclaration>())
          f.name.lexeme: f,
    };
    return all[name];
  }
}

final class _VmVisitor extends RecursiveAstVisitor<void> {
  _VmVisitor(this.path, this.functions, this.extensions, this.events);
  final String path;
  final _TopLevelFunctions functions;
  final Map<String, VmExtension> extensions;
  final Set<String> events;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    final args = <Expression>[
      for (final a in node.argumentList.arguments) a.argumentExpression,
    ];
    switch (node.methodName.name) {
      // A forwarder — the engine's own `registerFlutter3dExtension` handing
      // its parameters on to `dart:developer`, or `VmExtensions.register`
      // handing a plugin's handler on — names nothing of its own; the calls
      // of it are what the snapshot lists.
      case 'registerExtension' || 'registerFlutter3dExtension'
          when args.length >= 2 &&
              (args[0] is SimpleIdentifier || args[1] is SimpleIdentifier):
        break;
      case 'registerExtension' || 'registerFlutter3dExtension'
          when args.length >= 2:
        _register(
          node,
          args[0],
          args[1],
          _named(node, 'answers'),
          _named(node, 'aliases'),
        );
      case 'postToolEvent' when args.isNotEmpty:
        final kind = args.first;
        if (kind is! SimpleStringLiteral) {
          throw StateError(
            '$path:${node.offset}: postToolEvent with a kind that is not a '
            'string literal (${kind.toSource()}): the snapshot cannot name it',
          );
        }
        events.add('$gameEventPrefix${kind.value}');
      case 'postEvent' when args.isNotEmpty:
        if (args.first case final SimpleStringLiteral kind) {
          events.add(kind.value);
        }
    }
  }

  /// The expression a call passes for its named argument [name], or null.
  Expression? _named(MethodInvocation call, String name) => call
      .argumentList
      .arguments
      .whereType<NamedArgument>()
      .where((a) => a.name.lexeme == name)
      .firstOrNull
      ?.argumentExpression;

  void _register(
    MethodInvocation call,
    Expression name,
    Expression handler,
    Expression? answers,
    Expression? aliases,
  ) {
    VmExtension declared(VmExtension read, Map<String, Expression> bound) => (
      parameters: read.parameters,
      result: answers == null
          ? read.result
          : _strings(answers, bound, '${call.offset}: answers'),
      aliases: aliases == null
          ? const <String>[]
          : _strings(aliases, bound, '${call.offset}: aliases').toList(),
    );
    if (name is SimpleStringLiteral) {
      extensions[name.value] = declared(
        _handlerKeys(handler, const {}),
        const {},
      );
      return;
    }
    // A name built from a local helper's parameter: one extension per call
    // of that helper, each with the helper's parameters bound.
    final helper = call.thisOrAncestorOfType<FunctionDeclarationStatement>();
    final declaration = helper?.functionDeclaration;
    final scope = helper?.parent;
    if (name is! StringInterpolation || declaration == null || scope == null) {
      throw StateError(
        '$path:${call.offset}: an extension named ${name.toSource()}, which '
        'is neither a string literal nor built from a local helper\'s '
        'parameters',
      );
    }
    final parameters = declaration.functionExpression.parameters!.parameters;
    final calls = <MethodInvocation>[];
    scope.accept(_CallsOf(declaration.name.lexeme, calls));
    for (final use in calls) {
      final bound = _bind(parameters, use.argumentList);
      final text = StringBuffer();
      for (final element in name.elements) {
        switch (element) {
          case InterpolationString(:final value):
            text.write(value);
          case InterpolationExpression(
                expression: SimpleIdentifier(:final name),
              )
              when bound[name] is SimpleStringLiteral:
            text.write((bound[name]! as SimpleStringLiteral).value);
          default:
            throw StateError(
              '$path:${use.offset}: cannot read the extension name '
              '${name.toSource()} at this call',
            );
        }
      }
      extensions[text.toString()] = declared(
        _handlerKeys(handler, bound),
        bound,
      );
    }
  }

  /// The strings a set or list literal holds — each a string literal, or a
  /// spread of a local helper's parameter bound to such a literal. Anything
  /// else is refused rather than guessed.
  Set<String> _strings(
    Expression literal,
    Map<String, Expression> bound,
    String what,
  ) {
    final elements = switch (literal) {
      SetOrMapLiteral(:final elements) => elements,
      ListLiteral(:final elements) => elements,
      SimpleIdentifier(:final name) when bound[name] != null => null,
      _ => throw StateError(
        '$path:$what is not a literal of strings (${literal.toSource()})',
      ),
    };
    if (elements == null) {
      return _strings(
        bound[(literal as SimpleIdentifier).name]!,
        const {},
        what,
      );
    }
    return <String>{
      for (final element in elements)
        ...switch (element) {
          SimpleStringLiteral(:final value) => <String>{value},
          SpreadElement(:final expression) => _strings(expression, bound, what),
          _ => throw StateError(
            '$path:$what holds ${element.toSource()}, not a string literal',
          ),
        },
    };
  }

  VmExtension _handlerKeys(Expression handler, Map<String, Expression> bound) {
    if (handler is! FunctionExpression) {
      throw StateError(
        '$path:${handler.offset}: a handler that is not a closure '
        '(${handler.toSource()})',
      );
    }
    final params = handler.parameters!.parameters;
    final result = <String>{};
    handler.body.accept(_ResultReader(result));
    if (params.length < 2) {
      return (
        parameters: <String, String>{},
        result: result,
        aliases: const <String>[],
      );
    }
    final keys = <String, String>{};
    _readKeys(handler.body, params[1].name!.lexeme, bound, keys, <String>{});
    return (parameters: keys, result: result, aliases: const <String>[]);
  }

  /// The keys [node] reads from the map named [map], into [keys].
  void _readKeys(
    AstNode node,
    String map,
    Map<String, Expression> bound,
    Map<String, String> keys,
    Set<String> seen,
  ) {
    node.accept(
      _KeyReader(map, keys, (String callee, int? position, String? named) {
        // The map handed to [callee], at [position] or by [named].
        final local = bound[callee];
        final FunctionExpression? body;
        if (local is FunctionExpression) {
          body = local;
        } else {
          final name = local is SimpleIdentifier ? local.name : callee;
          body = functions[name]?.functionExpression;
        }
        if (body == null) return;
        final params = body.parameters?.parameters ?? const <FormalParameter>[];
        final FormalParameter? target = named != null
            ? params.where((p) => p.name?.lexeme == named).firstOrNull
            : (position! < params.length ? params[position] : null);
        final paramName = target?.name?.lexeme;
        if (paramName == null) return;
        final id = '${body.offset}:$paramName';
        if (!seen.add(id)) return;
        _readKeys(body.body, paramName, bound, keys, seen);
      }),
    );
  }
}

/// Every call of the local function [name] under a node.
final class _CallsOf extends RecursiveAstVisitor<void> {
  _CallsOf(this.name, this.calls);
  final String name;
  final List<MethodInvocation> calls;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.target == null && node.methodName.name == name) calls.add(node);
  }
}

/// [parameters] bound to what [arguments] pass for them.
Map<String, Expression> _bind(
  List<FormalParameter> parameters,
  ArgumentList arguments,
) {
  final out = <String, Expression>{};
  final positional = arguments.arguments.whereType<Expression>().toList();
  var i = 0;
  for (final p in parameters) {
    final name = p.name?.lexeme;
    if (name == null) continue;
    if (p.isNamed) {
      for (final a in arguments.arguments.whereType<NamedArgument>()) {
        if (a.name.lexeme == name) out[name] = a.argumentExpression;
      }
    } else if (i < positional.length) {
      out[name] = positional[i++];
    }
  }
  return out;
}

/// The type a handler parses the parameter read at [read] as: what the
/// expression around it does with the string.
String _parsedAs(IndexExpression read) {
  AstNode? at = read.parent;
  while (at is ParenthesizedExpression ||
      at is ArgumentList ||
      at is NamedArgument ||
      (at is BinaryExpression && at.operator.lexeme == '??')) {
    at = at!.parent;
  }
  return switch (at) {
    MethodInvocation(
      target: SimpleIdentifier(name: final type),
      methodName: SimpleIdentifier(name: 'parse' || 'tryParse'),
    )
        when type == 'int' ||
            type == 'double' ||
            type == 'num' ||
            type == 'bool' =>
      type == 'num' ? 'double' : type,
    MethodInvocation(methodName: SimpleIdentifier(name: 'jsonDecode')) =>
      'json',
    BinaryExpression(operator: Token(lexeme: '==' || '!='), :final rightOperand)
        when rightOperand is SimpleStringLiteral &&
            (rightOperand.value == 'true' || rightOperand.value == 'false') =>
      'bool',
    _ => 'string',
  };
}

/// The keys of the JSON objects a handler answers with: every string key of
/// a map literal handed to `jsonEncode`, and `*` for an answer built
/// somewhere the snapshot cannot read (a `toJson()`, a helper).
final class _ResultReader extends RecursiveAstVisitor<void> {
  _ResultReader(this.keys);
  final Set<String> keys;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    final args = <Expression>[
      for (final a in node.argumentList.arguments) a.argumentExpression,
    ];
    if (args.isEmpty) return;
    switch (node.methodName.name) {
      case 'jsonEncode':
        _read(args.first);
      case 'result'
          when node.target?.toSource().endsWith('ServiceExtensionResponse') ??
              false:
        final answer = args.first;
        if (answer is SimpleStringLiteral) return;
        if (answer is MethodInvocation &&
            answer.methodName.name == 'jsonEncode') {
          return;
        }
        keys.add('*');
    }
  }

  void _read(Expression e) {
    switch (e) {
      case SetOrMapLiteral(:final elements):
        for (final element in elements) {
          if (element case MapLiteralEntry(
            key: SimpleStringLiteral(:final value),
          )) {
            keys.add(value);
          } else {
            keys.add('*');
          }
        }
      case ConditionalExpression(:final thenExpression, :final elseExpression):
        _read(thenExpression);
        _read(elseExpression);
      case BinaryExpression(:final leftOperand, :final rightOperand)
          when e.operator.lexeme == '??':
        _read(leftOperand);
        _read(rightOperand);
      case ParenthesizedExpression(:final expression):
        _read(expression);
      default:
        keys.add('*');
    }
  }
}

/// Reads `map['key']`, and reports every call [map] is handed to.
final class _KeyReader extends RecursiveAstVisitor<void> {
  _KeyReader(this.map, this.keys, this.handedTo);
  final String map;
  final Map<String, String> keys;
  final void Function(String callee, int? position, String? named) handedTo;

  @override
  void visitIndexExpression(IndexExpression node) {
    super.visitIndexExpression(node);
    final target = node.target;
    final index = node.index;
    if (target is SimpleIdentifier &&
        target.name == map &&
        index is SimpleStringLiteral) {
      final type = _parsedAs(node);
      // Read as a string in one place and parsed in another, it is what the
      // parse says.
      keys[index.value] = keys[index.value] == null || type != 'string'
          ? type
          : keys[index.value]!;
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.target != null) return;
    _handed(node.methodName.name, node.argumentList);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    super.visitFunctionExpressionInvocation(node);
    if (node.function case SimpleIdentifier(:final name)) {
      _handed(name, node.argumentList);
    }
  }

  void _handed(String callee, ArgumentList arguments) {
    var position = 0;
    for (final a in arguments.arguments) {
      switch (a) {
        case NamedArgument(
              :final name,
              argumentExpression: SimpleIdentifier(name: final passed),
            )
            when passed == map:
          handedTo(callee, null, name.lexeme);
        case NamedArgument():
          break;
        case SimpleIdentifier(:final name) when name == map:
          handedTo(callee, position++, null);
        default:
          position++;
      }
    }
  }
}

// ---------------------------------------------------- servers from source

/// What a parameter of a tool-list function is given when the list is built
/// from source: a stand-in that names itself in the schema, so the snapshot
/// reads `{game}` and `{button}` where a host's own game supplies the words.
///
/// Keyed by the parameter's type. A tool list taking a type not here is
/// refused, naming it: add a stand-in, and say in its comment what the
/// placeholder stands for.
const Map<String, String> sourceProbes = <String, String>{
  'HeadlessGame': 'ProbeGame()',
};

const String _probesLibrary = r'''
// ignore_for_file: type=lint
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionWorld;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:stream_channel/stream_channel.dart';

/// [tool] marked with the condition a server offers it under.
ToolSpec offeredWhen(String when, ToolSpec tool) =>
    tool.copyWith(meta: <String, Object?>{'flutter3d/when': when});

/// The surface a server built over [tools] offers, as `ToolTableServer`
/// publishes it: renamed by [names], with its aliases and its schema tool.
Map<String, Object?> surfaceOf({
  required String name,
  required String? schemaVersion,
  required Map<String, String> aliases,
  required Map<String, ToolName> names,
  required List<ToolSpec> tools,
}) {
  final server = ToolTableServer<Object?, Object?>(
    StreamChannelController<String>().local,
    session: null,
    tools: <OfferedTool<Object?, Object?>>[
      for (final t in tools)
        OfferedTool<Object?, Object?>(t, (Object? s, Map<String, Object?> a) => null),
    ],
    toResult: (Object? answer) => ToolResult(),
    name: name,
    version: '0.0.0',
    instructions: '',
    schemaVersion: schemaVersion,
    aliases: aliases,
    names: names,
  );
  return <String, Object?>{
    'name': server.name,
    'schemaVersion': server.schemaVersion,
    'aliases': server.aliases,
    'tools': <Object?>[for (final t in server.offeredSpecs) t.toJson()],
  };
}

/// A game whose name, one button and one order are placeholders: what a
/// host's own game fills in is shown as `{game}`, `{button}`, `{order}` and
/// `{argument}`.
///
/// It is every kind of game a tool list asks about — an [OrderedGame] as well
/// as a [HeadlessGame] — so a tool offered only to some games is in the
/// snapshot, marked with the condition it is offered under.
final class ProbeGame extends OrderedGame {
  const ProbeGame();

  @override
  String get name => '{game}';

  @override
  Map<String, GameAction> get buttons =>
      const <String, GameAction>{'{button}': GameAction('{button}')};

  @override
  Map<String, GameOrder> get orders => const <String, GameOrder>{
    '{order}': GameOrder(
      description: '{what the order does}',
      arguments: <String, String>{'{argument}': '{what it means}'},
    ),
  };

  @override
  EntityRegistry registry() => throw UnsupportedError('a probe');

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) =>
      throw UnsupportedError('a probe');
}
''';

/// One parsed library file of a package, and its top-level declarations.
final class _Source {
  _Source(this.index, this.file, this.text, this.unit);
  final int index;
  final File file;
  final String text;
  final CompilationUnit unit;

  late final Map<String, AstNode> declarations = <String, AstNode>{
    for (final d in unit.declarations)
      if (d is FunctionDeclaration)
        d.name.lexeme: d
      else if (d is TopLevelVariableDeclaration)
        for (final v in d.variables.variables) v.name.lexeme: d,
  };

  /// The `dart:` and `package:` imports, minus [package]'s own.
  Iterable<String> imports(String package) sync* {
    for (final d in unit.directives.whereType<ImportDirective>()) {
      final uri = d.uri.stringValue ?? '';
      if (uri.startsWith('dart:') ||
          (uri.startsWith('package:') &&
              !uri.startsWith('package:$package/'))) {
        yield d.toSource();
      }
    }
  }
}

/// The servers of [package] — a package that needs Flutter — read from
/// source and printed by a program run under `dart run` in [work], a
/// directory of the workspace (its `package_config.json` resolves the
/// imports).
List<ServerSurface> serversFromSource(
  String package,
  Directory root,
  Directory work,
) {
  final sources = <_Source>[
    for (final (i, file) in libraryFiles(root).indexed)
      _Source(
        i,
        file,
        file.readAsStringSync(),
        parseString(
          content: file.readAsStringSync(),
          throwIfDiagnostics: false,
        ).unit,
      ),
  ];
  final needed = <_Source, Set<AstNode>>{};
  final emitted = <_Source, List<String>>{};
  void need(_Source from, AstNode node) {
    for (final name in _references(node)) {
      final here = from.declarations[name];
      final (source, declaration) = here != null
          ? (from, here)
          : name.startsWith('_')
          ? (null, null)
          : sources
                .map((s) => (s, s.declarations[name]))
                .firstWhere(
                  ((_Source, AstNode?) e) => e.$2 != null,
                  orElse: () => (from, null),
                );
      if (source == null || declaration == null) continue;
      if ((needed[source] ??= <AstNode>{}).add(declaration)) {
        need(source, declaration);
      }
    }
  }

  final servers = <String>[];
  for (final source in sources) {
    for (final c in source.unit.declarations.whereType<ClassDeclaration>()) {
      if (c.extendsClause?.superclass.name.lexeme != 'ToolTableServer') {
        continue;
      }
      final className = c.namePart.typeName.lexeme;
      final constructor = c.body.members
          .whereType<ConstructorDeclaration>()
          .single;
      final call = constructor.initializers
          .whereType<SuperConstructorInvocation>()
          .single;
      Expression? arg(String name) => call.argumentList.arguments
          .whereType<NamedArgument>()
          .where((NamedArgument e) => e.name.lexeme == name)
          .firstOrNull
          ?.argumentExpression;
      final tools = arg('tools');
      if (tools == null) {
        throw StateError('$className passes no tools: to its super call');
      }
      final listName = switch (tools) {
        MethodInvocation(target: null, :final methodName) => methodName.name,
        SimpleIdentifier(:final name) => name,
        _ => throw StateError(
          '$className passes tools: ${tools.toSource()}, which is not a call '
          'of a tool-list function or a tool-list getter',
        ),
      };
      final (listSource, list) = sources
          .map((s) => (s, s.declarations[listName] as FunctionDeclaration?))
          .firstWhere(
            ((_Source, FunctionDeclaration?) e) => e.$2 != null,
            orElse: () => throw StateError(
              '$className takes its tools from $listName, which is not a '
              'top-level function of $package',
            ),
          );
      final offers = _toolExpressions(listName, list!, listSource);
      final parameters =
          list.functionExpression.parameters?.parameters ??
          const <FormalParameter>[];
      final probeArgs = <String>[
        for (final p in parameters)
          switch (p) {
            FormalParameter(:final type?)
                when sourceProbes.containsKey(type.toSource()) =>
              sourceProbes[type.toSource()]!,
            _ => throw StateError(
              '$listName takes ${p.toSource()}, and there is no stand-in for '
              'it in sourceProbes',
            ),
          },
      ];
      final helpers = <String>{};
      String element(_Offer offer) {
        need(listSource, offer.tool);
        final String built;
        if (offer.helper case final FunctionDeclaration helper) {
          final toolOf = 'tool\$${helper.name.lexeme}';
          if (helpers.add(toolOf)) {
            (emitted[listSource] ??= <String>[]).add(
              'ToolSpec $toolOf${helper.functionExpression.parameters?.toSource() ?? '()'} '
              '=> ${offer.tool.toSource()};',
            );
          }
          need(listSource, offer.helperArguments!);
          built = '$toolOf${offer.helperArguments!.toSource()}';
        } else {
          built = offer.tool.toSource();
        }
        if (offer.guard case final IfElement guard) {
          need(listSource, guard.expression);
          final condition =
              '${guard.expression.toSource()}'
              '${guard.caseClause == null ? '' : ' ${guard.caseClause!.toSource()}'}';
          return 'if ($condition) offeredWhen(${jsonEncode(offer.when)}, $built)';
        }
        return built;
      }

      final offerName = 'offers\$$listName';
      (emitted[listSource] ??= <String>[]).add(
        'List<ToolSpec> $offerName${list.functionExpression.parameters?.toSource() ?? '()'} => <ToolSpec>[\n'
        '${offers.map((e) => '  ${element(e)},\n').join()}];',
      );
      String expression(String name, String fallback) {
        final e = arg(name);
        if (e == null) return fallback;
        need(source, e);
        return e.toSource();
      }

      final serverFunction = 'server\$$className';
      (emitted[source] ??= <String>[]).add(
        'Map<String, Object?> $serverFunction() => surfaceOf(\n'
        "  name: ${expression('name', "''")},\n"
        "  schemaVersion: ${expression('schemaVersion', 'null')},\n"
        "  aliases: ${expression('aliases', 'const <String, String>{}')},\n"
        "  names: ${expression('names', 'const <String, ToolName>{}')},\n"
        "  tools: f${listSource.index}.$offerName(${probeArgs.join(', ')}),\n"
        ');',
      );
      servers.add('f${source.index}.$serverFunction()');
    }
  }

  // One library per source file, so a private helper in one cannot collide
  // with a private helper of the same name in another.
  work.createSync(recursive: true);
  final files = <_Source>{...needed.keys, ...emitted.keys};
  final imports = <String>[
    "import 'probes.dart';",
    for (final s in files) "import 'f${s.index}.dart' as f${s.index};",
    // Unprefixed as well, for a declaration that names one in another file
    // of the package: a tool built by the package's own `mcpTool`.
    for (final s in files) "import 'f${s.index}.dart';",
  ];
  for (final s in files) {
    final body = StringBuffer()
      ..writeln('// Generated by tool/api from ${s.file.path}. Do not edit.')
      ..writeln('// ignore_for_file: type=lint')
      ..writeln(<String>{...s.imports(package), ...imports}.join('\n'))
      ..writeln();
    final copied = (needed[s] ?? const <AstNode>{}).toList()
      ..sort((AstNode a, AstNode b) => a.offset.compareTo(b.offset));
    for (final d in copied) {
      body
        ..writeln(s.text.substring(d.offset, d.end))
        ..writeln();
    }
    for (final e in emitted[s] ?? const <String>[]) {
      body
        ..writeln(e)
        ..writeln();
    }
    File('${work.path}/f${s.index}.dart').writeAsStringSync(body.toString());
  }
  File('${work.path}/probes.dart').writeAsStringSync(_probesLibrary);
  File('${work.path}/main.dart').writeAsStringSync(
    "import 'dart:convert';\n"
    '${imports.join('\n')}\n\n'
    'void main() => print(jsonEncode(<Object?>[\n'
    '${servers.map((s) => '  $s,\n').join()}]));\n',
  );
  final run = Process.runSync(Platform.resolvedExecutable, <String>[
    'run',
    'main.dart',
  ], workingDirectory: work.path);
  if (run.exitCode != 0) {
    throw StateError(
      'the tools of $package, read from source, did not run '
      '(exit ${run.exitCode}) — ${work.path}/main.dart:\n'
      '${run.stdout}\n${run.stderr}',
    );
  }
  final printed = (run.stdout as String).trim().split('\n').last;
  return <ServerSurface>[
    for (final s in jsonDecode(printed) as List)
      (s as Map).cast<String, Object?>(),
  ];
}

/// One element of a tool list, as the snapshot program rebuilds it.
///
/// [tool] is the `mcpTool(...)` expression, and [helper] the top-level function
/// it was written in when the element calls one (`_orderTool(ordered)`)
/// instead of spelling the tool out: the program gets a copy of that
/// function returning only the tool, called with the element's arguments.
/// [guard] is the collection `if` the element sits under, when the server
/// offers the tool to some hosts and not others; the snapshot program keeps
/// the condition, so the probe it builds the list for decides, and marks the
/// tool with [when] so the snapshot says it is conditional.
typedef _Offer = ({
  Expression tool,
  FunctionDeclaration? helper,
  ArgumentList? helperArguments,
  IfElement? guard,
  String? when,
});

/// The tools of each element of [list]'s list: each an `X(mcpTool(...),
/// handler)`, a call of a top-level function of [source] whose body is one,
/// or either of those under a collection `if` with no `else`.
List<_Offer> _toolExpressions(
  String name,
  FunctionDeclaration list,
  _Source source,
) {
  Expression? returnedBy(FunctionDeclaration f) =>
      switch (f.functionExpression.body) {
        ExpressionFunctionBody(:final expression) => expression,
        BlockFunctionBody(:final block)
            when block.statements.length == 1 &&
                block.statements.single is ReturnStatement =>
          (block.statements.single as ReturnStatement).expression,
        _ => null,
      };
  final returned = returnedBy(list);
  if (returned is! ListLiteral) {
    throw StateError(
      '$name does not return a list literal, so its tools cannot be read '
      'from source',
    );
  }
  Expression? toolOf(ArgumentList list) => switch (list.arguments.firstOrNull) {
    final Expression tool when _isTool(tool) => tool,
    _ => null,
  };
  Expression? direct(CollectionElement e) => switch (e) {
    MethodInvocation(:final argumentList) => toolOf(argumentList),
    InstanceCreationExpression(:final argumentList) => toolOf(argumentList),
    _ => null,
  };
  _Offer? offerOf(CollectionElement e, IfElement? guard) {
    final when = guard == null ? null : _whenOf(guard);
    if (direct(e) case final Expression tool) {
      return (
        tool: tool,
        helper: null,
        helperArguments: null,
        guard: guard,
        when: when,
      );
    }
    if (e case MethodInvocation(
      target: null,
      :final methodName,
      :final argumentList,
    )) {
      final helper = source.declarations[methodName.name];
      if (helper is FunctionDeclaration) {
        final returned = returnedBy(helper);
        final tool = returned == null ? null : direct(returned);
        if (tool != null) {
          return (
            tool: tool,
            helper: helper,
            helperArguments: argumentList,
            guard: guard,
            when: when,
          );
        }
      }
    }
    return null;
  }

  return <_Offer>[
    for (final element in returned.elements)
      switch (element) {
        IfElement(:final thenElement, elseElement: null)
            when offerOf(thenElement, element) != null =>
          offerOf(thenElement, element)!,
        _ when offerOf(element, null) != null => offerOf(element, null)!,
        _ => throw StateError(
          'an element of $name is not `X(mcpTool(...), handler)`, a call of a '
          'top-level function that returns one, or either under an `if` '
          'with no `else`, and cannot be read from source: '
          '${element.toSource().split('\n').first}',
        ),
      },
  ];
}

/// What a snapshot says about the hosts a guarded tool is offered to:
/// `game is OrderedGame` for `if (game case final OrderedGame ordered)`, the
/// condition as written for anything else.
String _whenOf(IfElement guard) => switch (guard) {
  IfElement(
    :final expression,
    caseClause: CaseClause(
      guardedPattern: GuardedPattern(
        pattern: DeclaredVariablePattern(:final type?),
        whenClause: null,
      ),
    ),
  ) =>
    '${expression.toSource()} is ${type.toSource()}',
  IfElement(:final expression, :final caseClause) =>
    '${expression.toSource()}'
        '${caseClause == null ? '' : ' ${caseClause.toSource()}'}',
};

/// Whether [e] builds a tool: `mcpTool(...)`, a package's own builder over
/// the schema library, or `ToolSpec(...)` written out.
bool _isTool(Expression e) => switch (e) {
  MethodInvocation(
    target: null,
    methodName: SimpleIdentifier(name: 'mcpTool' || 'ToolSpec'),
  ) =>
    true,
  InstanceCreationExpression(:final constructorName)
      when constructorName.type.name.lexeme == 'ToolSpec' =>
    true,
  _ => false,
};

/// The names [node] refers to — not the names it declares, labels, or the
/// members it reads off something else.
Set<String> _references(AstNode node) {
  final names = <String>{};
  node.accept(_References(names));
  return names;
}

final class _References extends RecursiveAstVisitor<void> {
  _References(this.names);
  final Set<String> names;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    final member = switch (parent) {
      Label() => true,
      PropertyAccess(:final propertyName) => identical(propertyName, node),
      PrefixedIdentifier(:final identifier) => identical(identifier, node),
      MethodInvocation(:final methodName, :final target) =>
        identical(methodName, node) && target != null,
      _ => false,
    };
    if (!member) names.add(node.name);
  }
}

// ------------------------------------------------------------ plugin tools

/// Where a plugin package's MCP tools are snapshotted, relative to the
/// package: beside its `.mcp`, which holds the servers it builds, if any.
String pluginSnapshotPathOf(String package) => 'api/$package.plugin.mcp';

/// What `--plugin` names: `package:<package>#<Plugin>`, the plugin class
/// exported by the package's own library, built with no arguments.
typedef PluginSource = ({String package, String className});

/// [text] read as a [PluginSource], or null when it is not one.
PluginSource? parsePluginSource(String text) {
  final match = RegExp(
    r'^package:([a-z_][a-z0-9_]*)#([A-Z]\w*)$',
  ).firstMatch(text.trim());
  if (match == null) return null;
  return (package: match[1]!, className: match[2]!);
}

/// The plugin source a committed `.plugin.mcp` was written from, from its
/// `# plugin` line; null when it has none.
PluginSource? pluginSourceIn(String snapshot) {
  final line = RegExp(
    r'^# plugin (\S+)$',
    multiLine: true,
  ).firstMatch(snapshot)?[1];
  return line == null ? null : parsePluginSource(line);
}

/// The tools [source]'s plugin adds to a project, one surface per namespace
/// with the schema version it declared — got by installing the plugin into
/// an engine with an empty `McpTools`, in a program run under `dart run` in
/// [work], a directory of the workspace.
List<ServerSurface> pluginSurfaces(PluginSource source, Directory work) {
  work.createSync(recursive: true);
  File('${work.path}/main.dart').writeAsStringSync('''
// Generated by tool/api for ${source.package}#${source.className}. Do not edit.
// ignore_for_file: type=lint
import 'dart:convert';

import 'package:flutter3d_mcp/project_tools.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:${source.package}/${source.package}.dart' as plugin;

void main() {
  final tools = McpTools();
  EngineLoop(
    input: InputState(),
    registries: <PluginRegistry>[tools],
    plugins: <Flutter3dPlugin>[plugin.${source.className}()],
  );
  final byNamespace = <String, List<Object?>>{};
  for (final t in tools.tools) {
    (byNamespace[t.namespace] ??= <Object?>[]).add(t.spec.toJson());
  }
  print(jsonEncode(<Object?>[
    for (final MapEntry(:key, :value) in byNamespace.entries)
      <String, Object?>{
        'name': key,
        'schemaVersion': tools.schemaVersions[key],
        'aliases': const <String, String>{},
        'tools': value,
      },
  ]));
}
''');
  final run = Process.runSync(Platform.resolvedExecutable, <String>[
    'run',
    'main.dart',
  ], workingDirectory: work.path);
  if (run.exitCode != 0) {
    throw StateError(
      'the plugin ${source.package}#${source.className} did not install '
      '(exit ${run.exitCode}) — ${work.path}/main.dart:\n'
      '${run.stdout}\n${run.stderr}',
    );
  }
  final printed = (run.stdout as String).trim().split('\n').last;
  return <ServerSurface>[
    for (final s in jsonDecode(printed) as List)
      (s as Map).cast<String, Object?>(),
  ];
}

/// [servers] — a plugin's namespaces — as `api/<package>.plugin.mcp`
/// holds them, with the `# plugin` line a check reruns it from.
String renderPluginMcp(PluginSource source, List<ServerSurface> servers) =>
    '# plugin package:${source.package}#${source.className}\n'
    '${renderMcp(source.package, servers).replaceFirst('dart run api_snapshot:schema_snapshot --update ${source.package}', 'dart run api_snapshot:schema_snapshot --update --plugin package:${source.package}#${source.className}')}';
