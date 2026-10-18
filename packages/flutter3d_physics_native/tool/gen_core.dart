/// Writes the core's calls and struct layouts from its header — P9, phase 12.
///
///     dart run tool/gen_core.dart          # write them
///     dart run tool/gen_core.dart --check  # exit 1 if they are out of date
///
/// The Dart side reaches the core the same way natively and in the browser:
/// a function a C function, every pointer an address — a native one through
/// `dart:ffi`, an offset into the WebAssembly module's memory on the web —
/// and the structs it fills as offsets into a block of that memory. This
/// reads `csrc/include/f3d_physics.h` and writes `lib/src/core/` from it, so
/// the header is the one place a signature is written. Assumes the build the
/// Dart side ships: f3d_real a float.
library;

import 'dart:io';

/// What the generator writes, by path.
Map<String, String> generate(String header) {
  final text = header.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  final functions = _functions(text);
  final structs = _structs(text);
  final docs = _Docs.read(header, functions);
  return <String, String>{
    'lib/src/core/calls_native.g.dart': _native(functions, docs),
    'lib/src/core/calls_web.g.dart': _web(functions, docs),
    'lib/src/core/layout.g.dart': _layout(structs, docs),
    'csrc/wasm/f3d_wasm_shim.c': shim(header),
  };
}

/// The header's comments, as the Dart doc comments of what they describe:
/// the comment right above a function's declaration, a struct's or one of
/// its fields'. Every function and every field must have one; the header is
/// where a call is documented, and the Dart side repeats it.
final class _Docs {
  _Docs._(this._functions, this._structs, this._fields, this._names);

  /// Reads the comments of [header] for [functions] and its structs.
  factory _Docs.read(String header, List<_Function> functions) {
    final names = {for (final f in functions) f.name};
    final ofFunction = <String, String>{};
    final ofStruct = <String, String>{};
    final ofField = <String, Map<String, String>>{};
    final missing = <String>[];
    for (final m in RegExp(
      r'F3D_API\s+[^;#{]*?\b(f3d_\w+)\s*\(',
    ).allMatches(header)) {
      if (_inComment(header, m.start)) continue;
      final comment = _commentBefore(header, m.start);
      if (comment == null) {
        missing.add(m.group(1)!);
      } else {
        ofFunction[m.group(1)!] = comment;
      }
    }
    for (final m in RegExp(
      r'typedef struct (F3d\w+) \{(.*?)\} \1;',
      dotAll: true,
    ).allMatches(header)) {
      if (_inComment(header, m.start)) continue;
      final name = m.group(1)!;
      final comment = _commentBefore(header, m.start);
      if (comment != null) ofStruct[name] = comment;
      final body = m.group(2)!;
      final fields = ofField[name] = <String, String>{};
      for (final f in RegExp(
        r'(\w+)\s+(\w+)(?:\[\d+\])?\s*;',
      ).allMatches(body)) {
        if (_inComment(body, f.start)) continue;
        final comment = _commentBefore(body, f.start);
        if (comment == null) {
          missing.add('$name.${f.group(2)}');
        } else {
          fields[f.group(2)!] = comment;
        }
      }
    }
    if (missing.isNotEmpty) {
      throw FormatException(
        'f3d_physics.h has no comment for: ${missing.join(', ')}',
      );
    }
    return _Docs._(ofFunction, ofStruct, ofField, names);
  }

  final Map<String, String> _functions;
  final Map<String, String> _structs;
  final Map<String, Map<String, String>> _fields;
  final Set<String> _names;

  /// The doc comment of function [f], at the top level.
  String function(_Function f) =>
      _doc(_functions[f.name]!, '', {for (final p in f.params) p.name});

  /// The doc comment of struct [name], at the top level.
  String struct(String name) => switch (_structs[name]) {
    final String c => _doc(c, '', const {}),
    null => '/// `$name`.\n',
  };

  /// The doc comment of field [field] of struct [name], in its class.
  String field(String name, String field) =>
      _doc(_fields[name]![field]!, '  ', const {});

  /// Whether [at] in [text] falls inside a C comment.
  static bool _inComment(String text, int at) {
    final before = text.substring(0, at);
    return before.lastIndexOf('/*') > before.lastIndexOf('*/');
  }

  /// The text of the C comment that ends right before [at] in [text], with
  /// nothing but white space between; null when there is none, or when it is
  /// a section rule (`/* ---- vehicles */`).
  static String? _commentBefore(String text, int at) {
    final before = text.substring(0, at).trimRight();
    if (!before.endsWith('*/')) return null;
    final start = before.lastIndexOf('/*');
    final inner = before.substring(start + 2, before.length - 2);
    if (RegExp(r'^\s*-+\s*[\w ]*$').hasMatch(inner)) return null;
    return inner;
  }

  /// [comment] as `///` lines at [indent], wrapped at 80 columns: its
  /// paragraphs kept, `[a_param]` named as the Dart parameter is, a call of
  /// the core's a link to its function here, and every other name of the
  /// header's in backticks.
  String _doc(String comment, String indent, Set<String> params) {
    final lines = comment
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^\s*\*?\s?'), '').trimRight());
    final paragraphs = <String>[];
    final current = <String>[];
    for (final line in [...lines, '']) {
      if (line.trim().isEmpty) {
        if (current.isNotEmpty) paragraphs.add(current.join(' '));
        current.clear();
      } else {
        current.add(line.trim());
      }
    }
    final width = 80 - indent.length - 4;
    final out = StringBuffer();
    for (final (i, paragraph) in paragraphs.indexed) {
      if (i > 0) out.write('$indent///\n');
      final text = paragraph
          .replaceAllMapped(
            RegExp(r'\[(\w+)\]'),
            (m) => params.contains(m.group(1))
                ? '[${_camel(m.group(1)!)}]'
                : '`${m.group(1)}`',
          )
          .replaceAllMapped(
            RegExp(r'(?<![\w`\[])([Ff]3[Dd]_?\w*)'),
            (m) => _names.contains(m.group(1))
                ? '[${m.group(1)}]'
                : '`${m.group(1)}`',
          );
      var line = '';
      for (final word in text.split(' ')) {
        if (line.isNotEmpty && line.length + 1 + word.length > width) {
          out.write('$indent/// $line\n');
          line = word;
        } else {
          line = line.isEmpty ? word : '$line $word';
        }
      }
      if (line.isNotEmpty) out.write('$indent/// $line\n');
    }
    return out.toString();
  }
}

/// [text] with Unix line ends: a Windows checkout has the sources and the
/// generated files with CRLF, and the generated text is the same text.
String _lf(String text) => text.replaceAll('\r\n', '\n');

/// [files] as `dart format` leaves them, so that formatting the package
/// does not make them out of date.
Map<String, String> _formatted(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('f3d_gen');
  try {
    final paths = <String, File>{};
    var i = 0;
    final kept = <String, String>{};
    for (final entry in files.entries) {
      if (!entry.key.endsWith('.dart')) {
        kept[entry.key] = entry.value;
        continue;
      }
      final f = File('${dir.path}/f${i++}.dart')
        ..writeAsStringSync(entry.value);
      paths[entry.key] = f;
    }
    final result = Process.runSync('dart', <String>['format', dir.path]);
    if (result.exitCode != 0) throw StateError('dart format: ${result.stderr}');
    return <String, String>{
      for (final entry in paths.entries)
        entry.key: _lf(entry.value.readAsStringSync()),
      ...kept,
    };
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main(List<String> args) {
  final files = _formatted(
    generate(_lf(File('csrc/include/f3d_physics.h').readAsStringSync())),
  );
  final check = args.contains('--check');
  var stale = false;
  for (final entry in files.entries) {
    final file = File(entry.key);
    final current = file.existsSync() ? _lf(file.readAsStringSync()) : '';
    if (current == entry.value) continue;
    if (check) {
      stderr.writeln(
        '${entry.key} is out of date: run dart run tool/gen_core.dart',
      );
      stale = true;
    } else {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(entry.value);
      stdout.writeln('wrote ${entry.key}');
    }
  }
  if (stale) exitCode = 1;
}

/// A C type as the generator sorts them.
enum _Kind { real, double, int32, uint32, uint64, pointer, none }

final class _Param {
  _Param(this.kind, this.name);
  final _Kind kind;
  final String name;
}

final class _Function {
  _Function(this.name, this.returns, this.params);
  final String name;
  final _Kind returns;
  final List<_Param> params;
}

/// The calls that may run long or allocate — a step, a world made or freed,
/// a query that walks the tree — go through the runtime's usual transition;
/// the rest are leaf calls.
const Set<String> _notLeaf = <String>{
  'f3d_world_create', 'f3d_world_destroy', 'f3d_world_step', //
  'f3d_world_set_threads', 'f3d_world_ray_cast', 'f3d_world_ray_cast_all',
  'f3d_world_overlap_shape', 'f3d_world_cast_shape', 'f3d_world_move_character',
  'f3d_world_create_hull', 'f3d_world_create_mesh', 'f3d_joint_create',
  'f3d_world_create_compound',
  'f3d_vehicle_create',
  'f3d_multibody_create',
  'f3d_shallow_create',
  'f3d_multibody_add_link',
  'f3d_joint_create_distance', 'f3d_joint_destroy', 'f3d_world_restore',
  'f3d_body_create', 'f3d_particles_create', 'f3d_particles_destroy',
  'f3d_debris_create', 'f3d_debris_destroy', 'f3d_debris_step',
  'f3d_cloth_create', 'f3d_cloth_destroy', 'f3d_cloth_step',
  'f3d_fluid_create', 'f3d_fluid_destroy', 'f3d_fluid_step',
  'f3d_buffer_alloc', 'f3d_buffer_free',
};

_Kind _kind(String type) {
  final t = type.replaceAll('const ', '').trim();
  if (t.endsWith('*')) return _Kind.pointer;
  switch (t) {
    case 'void':
      return _Kind.none;
    case 'f3d_real':
      return _Kind.real;
    case 'double':
      return _Kind.double;
    case 'int':
    case 'F3dBodyType':
    case 'F3dShapeKind':
    case 'F3dJointType':
    case 'F3dMaterialKind':
    case 'F3dLawProperty':
      return _Kind.int32;
    case 'uint32_t':
    case 'F3dVehicle':
    case 'F3dMultibody':
    case 'F3dShallow':
      return _Kind.uint32;
    case 'uint64_t':
    case 'F3dBody':
    case 'F3dJoint':
      return _Kind.uint64;
  }
  throw FormatException('a type the generator does not know: $type');
}

List<_Function> _functions(String text) {
  final found = <_Function>[];
  for (final m in RegExp(r'F3D_API\s+([^;#]*?)\s*;').allMatches(text)) {
    final declaration = m.group(1)!.split(RegExp(r'\s+')).join(' ');
    final parts = RegExp(
      r'^(.*?)\b(f3d_\w+)\s*\((.*)\)$',
    ).firstMatch(declaration);
    if (parts == null) throw FormatException('cannot read: $declaration');
    final params = <_Param>[];
    for (final raw in parts.group(3)!.split(',')) {
      final p = raw.trim();
      if (p.isEmpty || p == 'void') continue;
      final name = RegExp(r'(\w+)$').firstMatch(p)!.group(1)!;
      params.add(_Param(_kind(p.substring(0, p.length - name.length)), name));
    }
    found.add(_Function(parts.group(2)!, _kind(parts.group(1)!), params));
  }
  return found;
}

String _camel(String c) {
  final words = c.split('_');
  return words.first +
      words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
}

const String _banner =
    '// Generated by tool/gen_core.dart from csrc/include/f3d_physics.h: do not edit.\n';

String _native(List<_Function> functions, _Docs docs) {
  String ffi(_Kind k) => switch (k) {
    _Kind.real => 'Float',
    _Kind.double => 'Double',
    _Kind.int32 => 'Int32',
    _Kind.uint32 => 'Uint32',
    _Kind.uint64 => 'Uint64',
    _Kind.pointer => 'Pointer<Void>',
    _Kind.none => 'Void',
  };
  String raw(_Kind k) => switch (k) {
    _Kind.real || _Kind.double => 'double',
    _Kind.pointer => 'Pointer<Void>',
    _Kind.none => 'void',
    _Kind.int32 || _Kind.uint32 || _Kind.uint64 => 'int',
  };
  String dart(_Kind k) => switch (k) {
    _Kind.real || _Kind.double => 'double',
    _Kind.none => 'void',
    _Kind.int32 || _Kind.uint32 || _Kind.uint64 || _Kind.pointer => 'int',
  };
  final b = StringBuffer()
    ..write(_banner)
    ..write(
      '//\n// The core\'s calls natively: through dart:ffi, a pointer an address.\n',
    )
    ..write('// ignore_for_file: non_constant_identifier_names\n')
    ..write(
      "@DefaultAsset('package:flutter3d_physics_native/src/core/calls_native.g.dart')\n",
    )
    ..write('library;\n\n')
    ..write("import 'dart:ffi';\n");
  for (final f in functions) {
    final leaf = _notLeaf.contains(f.name) ? '' : 'isLeaf: true';
    final sig =
        '${ffi(f.returns)} Function(${f.params.map((p) => ffi(p.kind)).join(', ')})';
    final rawParams = f.params
        .map((p) => '${raw(p.kind)} ${_camel(p.name)}')
        .join(', ');
    final params = f.params
        .map((p) => '${dart(p.kind)} ${_camel(p.name)}')
        .join(', ');
    final args = f.params
        .map(
          (p) => p.kind == _Kind.pointer
              ? 'Pointer.fromAddress(${_camel(p.name)})'
              : _camel(p.name),
        )
        .join(', ');
    final call = '_${f.name}($args)';
    final body = f.returns == _Kind.pointer ? '$call.address' : call;
    b
      ..write(
        "\n@Native<$sig>(symbol: '${f.name}'${leaf.isEmpty ? '' : ', $leaf'})\n",
      )
      ..write('external ${raw(f.returns)} _${f.name}($rawParams);\n')
      ..write(docs.function(f))
      ..write('${dart(f.returns)} ${f.name}($params) => $body;\n');
  }
  return b.toString();
}

String _web(List<_Function> functions, _Docs docs) {
  // A 64-bit value crosses into the module as two 32-bit halves through a
  // shim of its own, f3d_wasm_shim.c, written with this; the rest are
  // numbers as they are.
  String js(_Kind k) => k == _Kind.none ? 'void' : 'JSNumber';
  final b = StringBuffer()
    ..write(_banner)
    ..write(
      '//\n// The core\'s calls in the browser: the WebAssembly module\'s exports, a\n',
    )
    ..write(
      '// pointer an offset into its memory, a 64-bit handle two 32-bit halves.\n',
    )
    ..write('// ignore_for_file: non_constant_identifier_names\n')
    ..write('library;\n\n')
    ..write("import 'dart:js_interop';\n\n")
    ..write("import 'module_web.dart';\n\n")
    ..write('extension type _Exports(JSObject _) implements JSObject {\n');
  for (final f in functions) {
    final params = <String>[];
    for (final p in f.params) {
      if (p.kind == _Kind.uint64) {
        params
          ..add('JSNumber ${_camel(p.name)}Low')
          ..add('JSNumber ${_camel(p.name)}High');
      } else {
        params.add('JSNumber ${_camel(p.name)}');
      }
    }
    final name = _wide(f) ? '${f.name}__w' : f.name;
    b.write(
      '  @JS(\'$name\')\n  external ${js(f.returns)} ${f.name}(${params.join(', ')});\n',
    );
  }
  b
    ..write('}\n\n')
    ..write('_Exports get _x => coreExports as _Exports;\n');
  for (final f in functions) {
    final params = f.params
        .map((p) => '${_number(p.kind)} ${_camel(p.name)}')
        .join(', ');
    final args = <String>[];
    for (final p in f.params) {
      final n = _camel(p.name);
      if (p.kind == _Kind.uint64) {
        args
          ..add('lowHalf($n).toJS')
          ..add('highHalf($n).toJS');
      } else {
        args.add('$n.toJS');
      }
    }
    final call = '_x.${f.name}(${args.join(', ')})';
    final String body;
    switch (f.returns) {
      case _Kind.none:
        body = call;
      case _Kind.real:
      case _Kind.double:
        body = '$call.toDartDouble';
      case _Kind.uint64:
        body = 'joinHalves($call.toDartInt, highResult())';
      case _Kind.uint32:
      case _Kind.pointer:
        body = '$call.toDartInt.toUnsigned(32)';
      case _Kind.int32:
        body = '$call.toDartInt';
    }
    final returns = f.returns == _Kind.none ? 'void' : _number(f.returns);
    b
      ..write(docs.function(f))
      ..write('$returns ${f.name}($params) => $body;\n');
  }
  return b.toString();
}

/// The Dart number a value of kind [k] crosses as.
String _number(_Kind k) => switch (k) {
  _Kind.real || _Kind.double => 'double',
  _Kind.int32 || _Kind.uint32 || _Kind.uint64 || _Kind.pointer => 'int',
  _Kind.none => throw ArgumentError('a value has no kind none'),
};

/// Whether a call takes or gives a 64-bit value, and so goes through the
/// shim.
bool _wide(_Function f) =>
    f.returns == _Kind.uint64 || f.params.any((p) => p.kind == _Kind.uint64);

/// The shim the WebAssembly build exports in place of each call that takes
/// or gives a 64-bit value: halves in, the low half out and the high half
/// kept for f3d_wasm_high.
String shim(String header) {
  final text = header.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  final b = StringBuffer()
    ..write(
      '/* Generated by tool/gen_core.dart from f3d_physics.h: do not edit.\n',
    )
    ..write(
      ' *\n * The WebAssembly build\'s exports for the calls that take or give a\n',
    )
    ..write(
      ' * 64-bit value, which JavaScript would have as a BigInt: two 32-bit halves\n',
    )
    ..write(
      ' * in, and out the low half, the high one kept for f3d_wasm_high. */\n',
    )
    ..write('#include "f3d_physics.h"\n\n')
    ..write('static uint32_t g_high;\n\n')
    ..write('F3D_API uint32_t f3d_wasm_high(void) { return g_high; }\n');
  String c(_Kind k) => switch (k) {
    _Kind.real => 'f3d_real',
    _Kind.double => 'double',
    _Kind.int32 => 'int',
    _Kind.uint32 => 'uint32_t',
    _Kind.uint64 => 'uint64_t',
    _Kind.pointer => 'void *',
    _Kind.none => 'void',
  };
  for (final f in _functions(text).where(_wide)) {
    final params = <String>[];
    final args = <String>[];
    for (final p in f.params) {
      if (p.kind == _Kind.uint64) {
        params
          ..add('uint32_t ${p.name}_low')
          ..add('uint32_t ${p.name}_high');
        args.add('((uint64_t)${p.name}_high << 32) | ${p.name}_low');
      } else {
        params.add('${c(p.kind)} ${p.name}');
        args.add(p.kind == _Kind.pointer ? '(void *)${p.name}' : p.name);
      }
    }
    final ret = f.returns == _Kind.uint64 ? 'uint32_t' : c(f.returns);
    final call = '${f.name}(${args.join(', ')})';
    final body = switch (f.returns) {
      _Kind.uint64 =>
        '  const uint64_t v = $call;\n  g_high = (uint32_t)(v >> 32);\n  return (uint32_t)v;',
      _Kind.none => '  $call;',
      _Kind.real ||
      _Kind.double ||
      _Kind.int32 ||
      _Kind.uint32 ||
      _Kind.pointer => '  return $call;',
    };
    b.write(
      '\nF3D_API $ret ${f.name}__w(${params.isEmpty ? 'void' : params.join(', ')}) {\n$body\n}\n',
    );
  }
  return b.toString();
}

final class _Field {
  _Field(this.name, this.kind, this.count);
  final String name;
  final _Kind kind;
  final int count;
}

Map<String, List<_Field>> _structs(String text) {
  final out = <String, List<_Field>>{};
  for (final m in RegExp(
    r'typedef struct (F3d\w+) \{(.*?)\} \1;',
    dotAll: true,
  ).allMatches(text)) {
    final fields = <_Field>[];
    for (final line in m.group(2)!.split(';')) {
      final f = line.trim();
      if (f.isEmpty) continue;
      final parts = RegExp(r'^(\w+)\s+(\w+)(?:\[(\d+)\])?$').firstMatch(f);
      if (parts == null) {
        throw FormatException('a field the generator cannot read: $f');
      }
      fields.add(
        _Field(
          parts.group(2)!,
          _kind(parts.group(1)!),
          int.parse(parts.group(3) ?? '1'),
        ),
      );
    }
    out[m.group(1)!] = fields;
  }
  return out;
}

String _layout(Map<String, List<_Field>> structs, _Docs docs) {
  int size(_Kind k) => switch (k) {
    _Kind.uint64 || _Kind.double => 8,
    _Kind.real ||
    _Kind.int32 ||
    _Kind.uint32 ||
    _Kind.pointer ||
    _Kind.none => 4,
  };
  final b = StringBuffer()
    ..write(_banner)
    ..write(
      '//\n// The structs the Dart side fills, as byte offsets into a block of the\n',
    )
    ..write(
      '// core\'s memory, laid out as C lays them out for the float build.\n',
    )
    ..write('library;\n');
  for (final entry in structs.entries) {
    var at = 0;
    var align = 4;
    b.write(
      '\n${docs.struct(entry.key)}'
      'abstract final class ${entry.key}Layout {\n',
    );
    for (final f in entry.value) {
      final s = size(f.kind);
      if (s > align) align = s;
      at = (at + s - 1) ~/ s * s;
      b
        ..write('  /// Byte offset of `${f.name}` in `${entry.key}`.\n  ///\n')
        ..write(docs.field(entry.key, f.name))
        ..write('  static const int ${_camel(f.name)} = $at;\n');
      at += s * f.count;
    }
    at = (at + align - 1) ~/ align * align;
    b
      ..write('\n  /// Size of `${entry.key}` in bytes, padded to its ')
      ..write('alignment.\n')
      ..write('  static const int size = $at;\n}\n');
  }
  return b.toString();
}
