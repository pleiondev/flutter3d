/// A Wasm assembler small enough to read: bytes by hand, for modules a test
/// needs and no toolchain should be required to make.
library;

import 'dart:convert';
import 'dart:typed_data';

/// An unsigned LEB128 number.
List<int> u32(int value) {
  final out = <int>[];
  var rest = value;
  do {
    var byte = rest & 0x7F;
    rest >>= 7;
    if (rest != 0) byte |= 0x80;
    out.add(byte);
  } while (rest != 0);
  return out;
}

/// A signed LEB128 number.
List<int> s32(int value) {
  final out = <int>[];
  var rest = value;
  while (true) {
    final byte = rest & 0x7F;
    rest >>= 7;
    final done =
        (rest == 0 && byte & 0x40 == 0) || (rest == -1 && byte & 0x40 != 0);
    out.add(done ? byte : byte | 0x80);
    if (done) return out;
  }
}

List<int> _name(String text) {
  final bytes = utf8.encode(text);
  return <int>[...u32(bytes.length), ...bytes];
}

List<int> _section(int id, List<int> body) => <int>[
  id,
  ...u32(body.length),
  ...body,
];

List<int> _vector(List<List<int>> items) => <int>[
  ...u32(items.length),
  for (final item in items) ...item,
];

// Instructions, as the tests write them.
const int unreachable = 0x00;
const int block = 0x02;
const int loop = 0x03;
const int ifOp = 0x04;
const int elseOp = 0x05;
const int end = 0x0B;
const int br = 0x0C;
const int brIf = 0x0D;
const int brTable = 0x0E;
const int call = 0x10;
const int drop = 0x1A;
const int localGet = 0x20;
const int localSet = 0x21;
const int localTee = 0x22;
const int globalGet = 0x23;
const int globalSet = 0x24;
const int memoryGrow = 0x40;
const int i32Add = 0x6A;
const int i32Sub = 0x6B;
const int i32Mul = 0x6C;
const int i32DivS = 0x6D;
const int i32RemS = 0x6F;
const int i32ShrU = 0x76;
const int i32Rotl = 0x77;
const int i32Clz = 0x67;
const int i32Ctz = 0x68;
const int i32Popcnt = 0x69;
const int i32GeS = 0x4E;
const int i32Eqz = 0x45;
const int blockVoid = 0x40;
const int blockI32 = 0x7F;

/// `i32.const value`.
List<int> konst(int value) => <int>[0x41, ...s32(value)];

/// `i32.load offset=0`, `i32.store offset=0`.
List<int> load() => <int>[0x28, 2, 0];
List<int> store() => <int>[0x36, 2, 0];

/// One module, put together a section at a time.
///
/// Imports are added before functions, so a function's index is the
/// number of imports plus its place among the functions, as in Wasm.
final class ModuleBuilder {
  final List<List<int>> _types = <List<int>>[];
  final List<List<int>> _imports = <List<int>>[];
  final List<int> _functions = <int>[];
  final List<List<int>> _bodies = <List<int>>[];
  final List<List<int>> _exports = <List<int>>[];
  final List<List<int>> _globals = <List<int>>[];
  final List<List<int>> _data = <List<int>>[];
  final List<List<int>> _extra = <List<int>>[];
  List<int>? _memory;
  int? _start;

  /// The index of a function type taking [params] i32 and returning
  /// [results], added the first time it is asked for.
  int type(int params, int results, {int valueType = 0x7F}) {
    final encoded = <int>[
      0x60,
      ...u32(params),
      for (var i = 0; i < params; i++) valueType,
      ...u32(results),
      for (var i = 0; i < results; i++) valueType,
    ];
    for (var i = 0; i < _types.length; i++) {
      if (_listEquals(_types[i], encoded)) return i;
    }
    _types.add(encoded);
    return _types.length - 1;
  }

  /// Imports [module].[name] as a function; returns its function index.
  int import(String name, int params, int results, {String module = 'f3d'}) {
    assert(_functions.isEmpty, 'imports come before functions');
    _imports.add(<int>[
      ..._name(module),
      ..._name(name),
      0,
      ...u32(type(params, results)),
    ]);
    return _imports.length - 1;
  }

  /// A function whose body is [code] (its final `end` added here); returns
  /// its function index.
  int function(int params, int results, List<int> code, {int locals = 0}) {
    _functions.add(type(params, results));
    final body = <int>[
      if (locals == 0) 0 else ...<int>[1, ...u32(locals), 0x7F],
      ...code,
      end,
    ];
    _bodies.add(<int>[...u32(body.length), ...body]);
    return _imports.length + _functions.length - 1;
  }

  void export(String name, int function) =>
      _exports.add(<int>[..._name(name), 0, ...u32(function)]);

  /// A mutable i32 global starting at [init]; returns its index.
  int global(int init, {bool mutable = true}) {
    _globals.add(<int>[0x7F, if (mutable) 1 else 0, ...konst(init), end]);
    return _globals.length - 1;
  }

  /// One memory of [min] pages, growing to [max] when given.
  void memory(int min, {int? max}) => _memory = <int>[
    1,
    if (max == null) 0 else 1,
    ...u32(min),
    if (max != null) ...u32(max),
  ];

  void data(int offset, List<int> bytes) => _data.add(<int>[
    0,
    ...konst(offset),
    end,
    ...u32(bytes.length),
    ...bytes,
  ]);

  void start(int function) => _start = function;

  /// A section written as raw bytes, for a test of what is refused.
  void section(int id, List<int> body) => _extra.add(_section(id, body));

  /// `f3d_abi` returning [abi], and `f3d_step` running [step] with the step
  /// in local 0 and dt in local 1.
  void abi({int abi = 1, List<int> step = const <int>[], int locals = 0}) {
    export('f3d_abi', function(0, 1, konst(abi)));
    export('f3d_step', function(2, 0, step, locals: locals));
  }

  Uint8List build() => Uint8List.fromList(<int>[
    0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00, //
    if (_types.isNotEmpty) ..._section(1, _vector(_types)),
    if (_imports.isNotEmpty) ..._section(2, _vector(_imports)),
    if (_functions.isNotEmpty)
      ..._section(3, _vector(<List<int>>[for (final t in _functions) u32(t)])),
    for (final extra in _extra) ...extra,
    if (_memory != null) ..._section(5, _memory!),
    if (_globals.isNotEmpty) ..._section(6, _vector(_globals)),
    if (_exports.isNotEmpty) ..._section(7, _vector(_exports)),
    if (_start != null) ..._section(8, u32(_start!)),
    if (_bodies.isNotEmpty) ..._section(10, _vector(_bodies)),
    if (_data.isNotEmpty) ..._section(11, _vector(_data)),
  ]);
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
