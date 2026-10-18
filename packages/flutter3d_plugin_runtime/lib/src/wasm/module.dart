import 'dart:convert';
import 'dart:typed_data';

import 'abi.dart';

// The instructions a compiled body is made of. Most keep the opcode Wasm
// gives them; `block`, `loop` and `end` are gone, resolved into the jumps of
// `br`, `br_if`, `br_table`, `if` and `else`, and a function's last `end` is
// a `return`. An `f32` is held as its bit pattern in an `i32` slot, so
// `f32.load`, `f32.store` and `f32.const` are the `i32` ones, and the two
// reinterpretations are nothing at all.
/// `unreachable`: traps with a [WasmTrapException].
const int opUnreachable = 0x00;

/// `if`: pops a condition and, where it is nought, jumps to the slot in
/// `a` (past the `else`, or past the end).
const int opIf = 0x04;

/// `else`, reached from the end of the true arm: jumps to the slot in `a`,
/// past the false arm.
const int opElse = 0x05;

/// `br`: takes the branch whose target entry is `a`.
const int opBr = 0x0C;

/// `br_if`: pops a condition and takes the branch at target entry `a`
/// where it is not nought.
const int opBrIf = 0x0D;

/// `br_table`: pops an index and takes target entry `a + index`, or
/// `a + b`, the default, for an index of `b` or more.
const int opBrTable = 0x0E;

/// `return`, and a function's last `end`: answers the top of the stack,
/// or nought for a function with no result.
const int opReturn = 0x0F;

/// `call`: calls the function at index `a`, imports first, with its
/// parameters popped and its result pushed.
const int opCall = 0x10;

/// `drop`: pops one value.
const int opDrop = 0x1A;

/// `select`: pops a condition and two values, and keeps the first where
/// the condition is not nought, the second otherwise.
const int opSelect = 0x1B;

/// `local.get`: pushes local `a`.
const int opLocalGet = 0x20;

/// `local.set`: pops into local `a`.
const int opLocalSet = 0x21;

/// `local.tee`: copies the top of the stack into local `a`, leaving it.
const int opLocalTee = 0x22;

/// `global.get`: pushes global `a`.
const int opGlobalGet = 0x23;

/// `global.set`: pops into global `a`.
const int opGlobalSet = 0x24;

/// `i32.load`, and `f32.load` as its bits: four bytes, little-endian, at
/// the popped address plus the offset `a`.
const int opLoad = 0x28;

/// `i32.load8_s`: one byte at the address plus `a`, sign-extended.
const int opLoad8S = 0x2C;

/// `i32.load8_u`: one byte at the address plus `a`, zero-extended.
const int opLoad8U = 0x2D;

/// `i32.load16_s`: two bytes, little-endian, at the address plus `a`,
/// sign-extended.
const int opLoad16S = 0x2E;

/// `i32.load16_u`: two bytes, little-endian, at the address plus `a`,
/// zero-extended.
const int opLoad16U = 0x2F;

/// `i32.store`, and `f32.store` as its bits: pops a value and an address
/// and writes four bytes, little-endian, at the address plus `a`.
const int opStore = 0x36;

/// `i32.store8`: writes the value's low byte at the address plus `a`.
const int opStore8 = 0x3A;

/// `i32.store16`: writes the value's low two bytes, little-endian, at the
/// address plus `a`.
const int opStore16 = 0x3B;

/// `memory.size`: pushes the memory's size in 64 KiB pages.
const int opMemorySize = 0x3F;

/// `memory.grow`: grows the memory by the popped count of pages and pushes
/// the size before, or minus one where [WasmLimits.memoryPages] would be
/// passed.
const int opMemoryGrow = 0x40;

/// `i32.const`, and `f32.const` as its bits: pushes `a`.
const int opConst = 0x41;

// The value types a module may name: `i32` in every module, `f32` in a
// render module (ABI 3).
/// The `i32` value type, which every module may name.
const int typeI32 = 0x7F;

/// The `f32` value type, which only a render module (ABI 3) may name.
const int typeF32 = 0x7D;

// The host functions an import may name, by what the interpreter calls.
/// The host function `field_len(field)`: how many values a field holds.
const int hostFieldLen = 0;

/// The host function `field_get(field, index)`: one value, in Q16.16
/// unless the field says otherwise.
const int hostFieldGet = 1;

/// The host function `field_set(field, index, value)`, for a writable
/// field.
const int hostFieldSet = 2;

/// The host function `publish(event, a, b)`: publishes a declared event
/// with two values.
const int hostPublish = 3;

/// The host function `field_frac(field)` (ABI 2): how many fraction bits a
/// field's values cross with.
const int hostFieldFrac = 4;

/// The render host function `param(index, component, value)`: sets one
/// float of a parameter of the step's stage.
const int hostParam = 5;

/// The render host function `param_floats(parameter, ptr, len)`: sets a
/// parameter from `len` floats in the module's memory at `ptr`.
const int hostParamFloats = 6;

/// The render host function `draw()`: says the step draws this frame.
const int hostDraw = 7;

/// The render host function `time()`: the frame's time in seconds, an
/// `f32`.
const int hostTime = 8;

/// The render host function `view_size(axis)`: the view's size along one
/// axis, in pixels.
const int hostViewSize = 9;

/// The render host function `light_code(light)`: the code of one of the
/// declaration's light types.
const int hostLightCode = 10;

/// One host function: what the interpreter calls, and its signature.
final class _HostImport {
  const _HostImport(this.host, this.type);

  final int host;
  final FunctionType type;
}

/// The host functions a step module may import. Which ABI each arrived in
/// is `wasmImportSince`; whether a module may use it is checked against the
/// ABI it says, at instantiation.
const Map<String, _HostImport> _stepImports = <String, _HostImport>{
  'field_len': _HostImport(hostFieldLen, FunctionType.i32(1, 1)),
  'field_get': _HostImport(hostFieldGet, FunctionType.i32(2, 1)),
  'field_set': _HostImport(hostFieldSet, FunctionType.i32(3, 0)),
  'publish': _HostImport(hostPublish, FunctionType.i32(3, 0)),
  'field_frac': _HostImport(hostFieldFrac, FunctionType.i32(1, 1)),
};

/// The host functions a render module may import (ABI 3): its commands, and
/// what the frame is.
const Map<String, _HostImport> _renderImports = <String, _HostImport>{
  'param': _HostImport(
    hostParam,
    FunctionType(<int>[typeI32, typeI32, typeF32], <int>[]),
  ),
  'param_floats': _HostImport(hostParamFloats, FunctionType.i32(3, 0)),
  'draw': _HostImport(hostDraw, FunctionType.i32(0, 0)),
  'time': _HostImport(hostTime, FunctionType(<int>[], <int>[typeF32])),
  'view_size': _HostImport(hostViewSize, FunctionType.i32(1, 1)),
  'light_code': _HostImport(hostLightCode, FunctionType.i32(1, 1)),
};

/// A function's signature: the type of each parameter and of its result.
final class FunctionType {
  /// A signature taking [paramTypes] and returning [resultTypes], each a
  /// [typeI32] or [typeF32].
  const FunctionType(this.paramTypes, this.resultTypes);

  /// A signature of [params] `i32`s returning [results] of them.
  const FunctionType.i32(int params, int results)
    : paramTypes = params == 0
          ? const <int>[]
          : params == 1
          ? const <int>[typeI32]
          : params == 2
          ? const <int>[typeI32, typeI32]
          : const <int>[typeI32, typeI32, typeI32],
      resultTypes = results == 0 ? const <int>[] : const <int>[typeI32];

  /// The value type of each parameter, in order.
  final List<int> paramTypes;

  /// The value type of the result, or empty for none: never more than one.
  final List<int> resultTypes;

  /// How many values it takes.
  int get params => paramTypes.length;

  /// How many it returns: nought or one.
  int get results => resultTypes.length;

  @override
  bool operator ==(Object other) =>
      other is FunctionType &&
      _same(other.paramTypes, paramTypes) &&
      _same(other.resultTypes, resultTypes);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(paramTypes), Object.hashAll(resultTypes));

  @override
  String toString() =>
      '(${paramTypes.map(_typeName).join(', ')}) -> '
      '(${resultTypes.map(_typeName).join(', ')})';

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

String _typeName(int type) => type == typeF32 ? 'f32' : 'i32';

/// One function body, validated and flattened into jumps.
///
/// [ops] holds an instruction per slot; [a] and [b] its immediates. A branch
/// names an entry of [targets], three numbers each: the slot to go to, how
/// many values it carries (nought or one), and the operand stack's height
/// after it — all worked out at decode, so a branch at run time is two
/// assignments.
final class CompiledFunction {
  /// A body made by decode, already validated; nothing is checked here.
  const CompiledFunction({
    required this.type,
    required this.localCount,
    required this.maxHeight,
    required this.ops,
    required this.a,
    required this.b,
    required this.targets,
  });

  /// The function's signature.
  final FunctionType type;

  /// Parameters and declared locals together.
  final int localCount;

  /// The deepest the operand stack gets.
  final int maxHeight;

  /// One instruction per slot: an `op…` constant or another Wasm opcode.
  final List<int> ops;

  /// Each slot's first immediate: an index, an offset, a constant or a jump.
  final List<int> a;

  /// Each slot's second immediate, where an instruction has one: a
  /// `br_table`'s count of labels.
  final List<int> b;

  /// The branch targets, three numbers each: the slot, the count of values
  /// carried and the stack height after.
  final List<int> targets;
}

/// A global's starting value — an `f32`'s as its bits — and whether it may
/// change.
final class ModuleGlobal {
  /// A global starting at [init], of [type], an `i32` by default.
  const ModuleGlobal({
    required this.mutable,
    required this.init,
    this.type = typeI32,
  });

  /// Whether `global.set` may change it.
  final bool mutable;

  /// Its starting value, an `f32`'s as its bits.
  final int init;

  /// `i32`, or `f32` in a render module.
  final int type;
}

/// Bytes copied into memory at instantiation.
final class DataSegment {
  /// The [bytes] to copy into memory at [offset].
  const DataSegment(this.offset, this.bytes);

  /// Where in memory the bytes go, in bytes from the start.
  final int offset;

  /// The bytes copied.
  final Uint8List bytes;
}

/// The globals a save of [module] holds by name, whichever runtime ran it:
/// each mutable global the module exports, by its export name, to its
/// index. What every runtime can read and write, the browser's included,
/// so a save holds the same globals whichever wrote it.
Map<String, int> savedGlobalsOf(WasmModule module) => <String, int>{
  for (final MapEntry(key: name, value: index) in module.globalExports.entries)
    if (module.globals[index].mutable) name: index,
};

/// A Wasm module of the plugin ABI: decoded, validated and compiled, ready
/// for any [WasmRuntime].
///
/// **Refused at load, not at the first step.** [decode] reads every section
/// and every instruction before it answers, so a module that uses a 64-bit
/// value, imports something its ABI does not offer or branches out of its
/// own body never gets as far as an engine. Each refusal names what it found
/// and where. The browser runtime runs this check too, so the same bytes are
/// refused everywhere.
///
/// **Of one [kind], said by whoever decodes it**: a step module is `i32`
/// only and exports `f3d_step`; a render module may compute in `f32` and
/// exports `f3d_render_node`. The `.f3dplugin` section that declares a
/// module says which, so the same bytes are never read as both.
final class WasmModule {
  WasmModule._({
    required this.bytes,
    required this.kind,
    required this._functionTypes,
    required this.imports,
    required this.importNames,
    required this._functions,
    required this.memoryMin,
    required this.memoryMax,
    required this._globals,
    required this.functionExports,
    required this.globalExports,
    required this.memoryExport,
    required this.start,
    required this._data,
  });

  /// The bytes it was decoded from, for a runtime that compiles them itself.
  final Uint8List bytes;

  /// Whether it steps the simulation or drives a render node.
  final WasmModuleKind kind;

  // What the interpreter runs, read through [WasmModuleInternals]: the
  // compiled code is this package's own shape, not part of its API.
  final List<FunctionType> _functionTypes;

  /// The host function behind each imported function, by function index.
  final List<int> imports;

  /// The name of each imported function, by function index — what the
  /// module asks the host for, checked against its ABI when it starts.
  final List<String> importNames;

  final List<CompiledFunction> _functions;

  /// The memory's starting pages, or null for a module with no memory.
  final int? memoryMin;

  /// The most pages the module says its memory may grow to, if it says.
  final int? memoryMax;

  final List<ModuleGlobal> _globals;

  /// Exported functions, by export name.
  final Map<String, int> functionExports;

  /// Exported globals, by export name.
  final Map<String, int> globalExports;

  /// The name the memory is exported under, if it is.
  final String? memoryExport;

  /// The start function's index, if there is one.
  final int? start;

  final List<DataSegment> _data;

  /// `f3d_abi`'s function index.
  int get abiFunction => functionExports['f3d_abi']!;

  /// `f3d_step`'s function index; a step module has one.
  int get stepFunction => functionExports['f3d_step']!;

  /// `f3d_render_node`'s function index; a render module has one.
  int get renderFunction => functionExports[wasmRenderNodeExport]!;

  /// Reads and checks [bytes] as a module of [kind]. Throws [WasmException]
  /// with a sentence naming the section, the instruction or the import that
  /// a module of that kind may not have.
  static WasmModule decode(
    Uint8List bytes, {
    WasmModuleKind kind = WasmModuleKind.step,
  }) => _Decoder(bytes, kind).decode();
}

/// The compiled parts of a [WasmModule] the runtimes in this package read.
///
/// Not exported: their types are the interpreter's own, which may change
/// in any release, so a runtime from outside compiles [WasmModule.bytes]
/// itself.
extension WasmModuleInternals on WasmModule {
  /// Every function's signature by function index: the imports first.
  List<FunctionType> get functionTypes => _functionTypes;

  /// The module's own functions, from function index `imports.length` on.
  List<CompiledFunction> get functions => _functions;

  /// Each global's starting value and whether it may change.
  List<ModuleGlobal> get globals => _globals;

  /// The bytes copied into memory at instantiation.
  List<DataSegment> get data => _data;
}

Never _refuse(String message) => throw WasmException(message);

String _hex(int value) => '0x${value.toRadixString(16).padLeft(2, '0')}';

String _abiOnlyI32(String what) =>
    '$what: ABI $wasmPluginAbi is 32-bit integers only, so one module gives '
    'one answer on the VM, in a browser and on a server';

String _renderOnlyI32F32(String what) =>
    '$what: a render module computes in i32 and f32 only, the values a '
    'shader\'s parameters are made of';

/// Reads bytes, LEB128 numbers and names, refusing anything that runs past
/// its end.
final class _Reader {
  _Reader(this.bytes, this.position, this.end);

  final Uint8List bytes;
  int position;
  final int end;

  bool get atEnd => position >= end;

  int byte() {
    if (position >= end) _refuse('the module ends in the middle of a value');
    return bytes[position++];
  }

  int peek() {
    if (position >= end) _refuse('the module ends in the middle of a value');
    return bytes[position];
  }

  /// An unsigned LEB128 number of at most 32 bits, built by multiplying
  /// rather than shifting, so it is the same number under JavaScript.
  int u32() {
    var result = 0;
    var scale = 1;
    for (var i = 0; i < 5; i++) {
      final b = byte();
      result += (b & 0x7F) * scale;
      if (b & 0x80 == 0) {
        if (result > 0xFFFFFFFF) _refuse('a number is wider than 32 bits');
        return result;
      }
      scale *= 128;
    }
    _refuse('a number is encoded in more than five bytes');
  }

  /// A signed LEB128 number of at most 32 bits.
  int s32() {
    var result = 0;
    var scale = 1;
    for (var i = 0; i < 5; i++) {
      final b = byte();
      result += (b & 0x7F) * scale;
      scale *= 128;
      if (b & 0x80 == 0) {
        if (b & 0x40 != 0) result -= scale;
        if (result < -0x80000000 || result > 0x7FFFFFFF) {
          _refuse('a constant is wider than 32 bits');
        }
        return result;
      }
    }
    _refuse('a constant is encoded in more than five bytes');
  }

  /// Four bytes, little-endian, as a signed 32-bit number: an `f32.const`'s
  /// bits.
  int bits32() {
    final raw = take(4);
    return ByteData.sublistView(raw).getInt32(0, Endian.little);
  }

  Uint8List take(int count) {
    if (position + count > end) _refuse('a section runs past its end');
    final out = Uint8List.sublistView(bytes, position, position + count);
    position += count;
    return out;
  }

  String name() {
    final raw = take(u32());
    try {
      return utf8.decode(raw);
    } on FormatException {
      _refuse('a name is not UTF-8');
    }
  }

  _Reader section(int size) {
    if (position + size > end) _refuse('a section runs past the module');
    final inner = _Reader(bytes, position, position + size);
    position += size;
    return inner;
  }
}

final class _Decoder {
  _Decoder(this.bytes, this.kind);

  final Uint8List bytes;
  final WasmModuleKind kind;

  /// Whether `f32` may appear: in a render module.
  bool get floats => kind == WasmModuleKind.render;

  final List<FunctionType> _types = <FunctionType>[];
  final List<FunctionType> _functionTypes = <FunctionType>[];
  final List<int> _imports = <int>[];
  final List<String> _importNames = <String>[];
  final List<int> _declared = <int>[];
  int? _memoryMin;
  int? _memoryMax;
  final List<ModuleGlobal> _globals = <ModuleGlobal>[];
  final Map<String, int> _functionExports = <String, int>{};
  final Map<String, int> _globalExports = <String, int>{};
  String? _memoryExport;
  int? _start;
  final List<DataSegment> _data = <DataSegment>[];
  _Reader? _code;

  /// Reads one value type, refusing every one this module's kind does not
  /// compute in, with the reason.
  int valueType(int type, String where) {
    switch (type) {
      case typeI32:
        return typeI32;
      case typeF32 when floats:
        return typeF32;
      case 0x7E:
        _refuse(_onlyOurs('$where uses an i64'));
      case typeF32:
        _refuse(_abiOnlyI32('$where uses an f32'));
      case 0x7C:
        _refuse(_onlyOurs('$where uses an f64'));
      case 0x7B:
        _refuse(_onlyOurs('$where uses a v128'));
      case 0x70 || 0x6F:
        _refuse(
          '$where uses a reference type; references and tables are not '
          'in ABI $wasmPluginAbi',
        );
      default:
        _refuse('$where names value type ${_hex(type)}, which is not Wasm');
    }
  }

  /// The refusal of a value this module's kind does not compute in.
  String _onlyOurs(String what) =>
      floats ? _renderOnlyI32F32(what) : _abiOnlyI32(what);

  WasmModule decode() {
    final r = _Reader(bytes, 0, bytes.length);
    if (bytes.length < 8 ||
        bytes[0] != 0x00 ||
        bytes[1] != 0x61 ||
        bytes[2] != 0x73 ||
        bytes[3] != 0x6D) {
      _refuse('these bytes are not a Wasm module: it starts with "\\0asm"');
    }
    if (bytes[4] != 1 || bytes[5] != 0 || bytes[6] != 0 || bytes[7] != 0) {
      _refuse('the module is not Wasm binary version 1');
    }
    r.position = 8;
    final seen = <int>{};
    while (!r.atEnd) {
      final id = r.byte();
      final body = r.section(r.u32());
      if (id != 0 && !seen.add(id)) _refuse('section $id appears twice');
      switch (id) {
        case 0:
          break; // custom: names, producers — nothing the engine reads
        case 1:
          _typeSection(body);
        case 2:
          _importSection(body);
        case 3:
          _functionSection(body);
        case 4:
          _refuse(
            'the module has a table (section 4); call_indirect and '
            'tables are not in ABI $wasmPluginAbi',
          );
        case 5:
          _memorySection(body);
        case 6:
          _globalSection(body);
        case 7:
          _exportSection(body);
        case 8:
          _start = _function(body.u32(), 'the start section');
        case 9:
          _refuse(
            'the module has element segments (section 9); tables are '
            'not in ABI $wasmPluginAbi',
          );
        case 10:
          _code = body;
        case 11:
          _dataSection(body);
        // ignore: no-equal-switch-case, each skipped section keeps its own reason.
        case 12:
          break; // the data count, which only bulk memory needs
        default:
          _refuse('section $id is not a Wasm section');
      }
    }
    final functions = _codeSection();
    _checkExports();
    final start = _start;
    if (start != null &&
        _functionTypes[start] != const FunctionType.i32(0, 0)) {
      _refuse(
        'the start function takes or returns values; it must take '
        'none and return none',
      );
    }
    return WasmModule._(
      bytes: bytes,
      kind: kind,
      functionTypes: List<FunctionType>.unmodifiable(_functionTypes),
      imports: List<int>.unmodifiable(_imports),
      importNames: List<String>.unmodifiable(_importNames),
      functions: List<CompiledFunction>.unmodifiable(functions),
      memoryMin: _memoryMin,
      memoryMax: _memoryMax,
      globals: List<ModuleGlobal>.unmodifiable(_globals),
      functionExports: Map<String, int>.unmodifiable(_functionExports),
      globalExports: Map<String, int>.unmodifiable(_globalExports),
      memoryExport: _memoryExport,
      start: start,
      data: List<DataSegment>.unmodifiable(_data),
    );
  }

  int _function(int index, String where) {
    if (index >= _functionTypes.length) {
      _refuse(
        '$where names function $index, and the module has '
        '${_functionTypes.length}',
      );
    }
    return index;
  }

  void _typeSection(_Reader r) {
    for (var i = r.u32(); i > 0; i--) {
      if (r.byte() != 0x60) _refuse('type ${_types.length} is not a function');
      final params = <int>[
        for (var p = r.u32(); p > 0; p--)
          valueType(r.byte(), 'type ${_types.length}'),
      ];
      final results = <int>[
        for (var p = r.u32(); p > 0; p--)
          valueType(r.byte(), 'type ${_types.length}'),
      ];
      if (results.length > 1) {
        _refuse(
          'type ${_types.length} returns ${results.length} values; a '
          'function returns at most one in ABI $wasmPluginAbi',
        );
      }
      _types.add(
        FunctionType(
          List<int>.unmodifiable(params),
          List<int>.unmodifiable(results),
        ),
      );
    }
  }

  FunctionType _type(int index, String where) {
    if (index >= _types.length) {
      _refuse(
        '$where names type $index, and the module declares '
        '${_types.length}',
      );
    }
    return _types[index];
  }

  void _importSection(_Reader r) {
    for (var i = r.u32(); i > 0; i--) {
      final module = r.name();
      final name = r.name();
      final kind = r.byte();
      final what = 'the import "$module.$name"';
      if (kind != 0) {
        final thing = switch (kind) {
          1 => 'a table',
          2 => 'a memory',
          3 => 'a global',
          _ => 'something that is not Wasm',
        };
        _refuse(
          '$what is $thing; ABI $wasmPluginAbi imports functions '
          'only, and the module brings its own memory',
        );
      }
      final type = _type(r.u32(), what);
      final offered = floats ? _renderImports : _stepImports;
      final host = offered[name];
      if (module != 'f3d' || host == null) {
        final other = (floats ? _stepImports : _renderImports)[name];
        if (module == 'f3d' && other != null) {
          _refuse(
            floats
                ? '$what is a step module\'s: a render module runs outside '
                      'the simulation and imports f3d.param, '
                      'f3d.param_floats, f3d.draw, f3d.time, f3d.view_size '
                      'and f3d.light_code'
                : '$what is a render module\'s (ABI 3): a module the '
                      '"wasm" section declares steps the simulation, and a '
                      'render module is declared under "wasmRender"',
          );
        }
        _refuse(
          floats
              ? '$what is not one ABI $wasmPluginAbi offers a render module. '
                    'A render module imports f3d.param, f3d.param_floats, '
                    'f3d.draw, f3d.time, f3d.view_size and f3d.light_code, '
                    'and nothing else: there is no file, clock or network '
                    'to reach'
              : '$what is not one ABI $wasmPluginAbi offers. A module '
                    'imports f3d.field_len, f3d.field_get, f3d.field_set, '
                    'f3d.publish and f3d.field_frac, and nothing else: there '
                    'is no file, clock or network to reach',
        );
      }
      if (type != host.type) {
        _refuse(
          '$what takes ${type.params} and returns ${type.results}'
          '${type.params == host.type.params && type.results == host.type.results ? ' as $type' : ''}; '
          'ABI $wasmPluginAbi has it take ${host.type.params} and return '
          '${host.type.results}${floats ? ' as ${host.type}' : ''}',
        );
      }
      _imports.add(host.host);
      _importNames.add(name);
      _functionTypes.add(type);
    }
  }

  void _functionSection(_Reader r) {
    for (var i = r.u32(); i > 0; i--) {
      final index = r.u32();
      _declared.add(index);
      _functionTypes.add(_type(index, 'function ${_functionTypes.length}'));
    }
  }

  void _memorySection(_Reader r) {
    final count = r.u32();
    if (count > 1) {
      _refuse(
        'the module declares $count memories; ABI $wasmPluginAbi has '
        'one',
      );
    }
    if (count == 0) return;
    final flags = r.byte();
    if (flags > 1) {
      _refuse(
        'the memory is shared or 64-bit (flags ${_hex(flags)}); ABI '
        '$wasmPluginAbi has one plain memory',
      );
    }
    _memoryMin = r.u32();
    if (flags == 1) {
      _memoryMax = r.u32();
      if (_memoryMax! < _memoryMin!) {
        _refuse('the memory may grow to fewer pages than it starts with');
      }
    }
  }

  /// One constant expression of [type]: an `i32.const`, or in a render
  /// module an `f32.const` for an `f32`, as its bits.
  int _constant(_Reader r, String where, {int type = typeI32}) {
    final op = r.byte();
    final int value;
    if (type == typeF32 && op == 0x43) {
      value = r.bits32();
    } else if (type == typeI32 && op == opConst) {
      value = r.s32();
    } else {
      _refuse(
        type == typeF32
            ? '$where does not start from f32.const; a global of a render '
                  'module starts from one constant of its type'
            : '$where does not start from i32.const; in ABI '
                  '$wasmPluginAbi it must',
      );
    }
    if (r.byte() != 0x0B) {
      _refuse(
        '$where is more than one ${_typeName(type)}.const; in ABI '
        '$wasmPluginAbi it is one',
      );
    }
    return value;
  }

  void _globalSection(_Reader r) {
    for (var i = r.u32(); i > 0; i--) {
      final where = 'global ${_globals.length}';
      final type = valueType(r.byte(), where);
      final mutable = switch (r.byte()) {
        0 => false,
        1 => true,
        _ => _refuse('$where is neither mutable nor immutable'),
      };
      _globals.add(
        ModuleGlobal(
          mutable: mutable,
          init: _constant(r, where, type: type),
          type: type,
        ),
      );
    }
  }

  void _exportSection(_Reader r) {
    final names = <String>{};
    for (var i = r.u32(); i > 0; i--) {
      final name = r.name();
      if (!names.add(name)) _refuse('two exports are named "$name"');
      final kind = r.byte();
      final index = r.u32();
      switch (kind) {
        case 0:
          _functionExports[name] = _function(index, 'the export "$name"');
        case 2:
          if (index != 0 || _memoryMin == null) {
            _refuse(
              'the export "$name" names a memory the module does not '
              'have',
            );
          }
          _memoryExport = name;
        case 3:
          if (index >= _globals.length) {
            _refuse(
              'the export "$name" names global $index, and the module '
              'has ${_globals.length}',
            );
          }
          _globalExports[name] = index;
        default:
          _refuse(
            'the export "$name" is a table or not Wasm; ABI '
            '$wasmPluginAbi has no tables',
          );
      }
    }
  }

  void _dataSection(_Reader r) {
    for (var i = r.u32(); i > 0; i--) {
      final where = 'data segment ${_data.length}';
      final flags = r.u32();
      if (flags == 1) {
        _refuse(
          '$where is passive; bulk memory is not in ABI '
          '$wasmPluginAbi',
        );
      }
      if (flags == 2 && r.u32() != 0) {
        _refuse('$where names a second memory; ABI $wasmPluginAbi has one');
      }
      if (flags > 2) _refuse('$where has flags $flags, which are not Wasm');
      if (_memoryMin == null) {
        _refuse('$where fills a memory the module does not have');
      }
      final offset = _constant(r, '$where\'s offset');
      _data.add(DataSegment(offset & 0xFFFFFFFF, r.take(r.u32())));
    }
  }

  void _checkExports() {
    final abi = _functionExports['f3d_abi'];
    if (abi == null) {
      _refuse(
        'the module exports no f3d_abi, so it does not say which ABI '
        'it was written for; export f3d_abi() returning '
        '$wasmPluginAbi',
      );
    }
    if (_functionTypes[abi] != const FunctionType.i32(0, 1)) {
      _refuse('f3d_abi must take nothing and return an i32');
    }
    if (floats) {
      final node = _functionExports[wasmRenderNodeExport];
      if (node == null) {
        _refuse(
          'the module is declared under "wasmRender" and exports no '
          '$wasmRenderNodeExport(i32 frame, i32 view), so there is nothing '
          'to call each frame',
        );
      }
      if (_functionTypes[node] != const FunctionType.i32(2, 0)) {
        _refuse(
          '$wasmRenderNodeExport must take two i32 — the frame and the '
          'view — and return nothing',
        );
      }
      return;
    }
    final step = _functionExports['f3d_step'];
    if (step == null) {
      _refuse(
        'the module exports no f3d_step(i32 step, i32 dt), so there '
        'is nothing to run each step',
      );
    }
    if (_functionTypes[step] != const FunctionType.i32(2, 0)) {
      _refuse(
        'f3d_step must take two i32 — the step and dt in Q16.16 — and '
        'return nothing',
      );
    }
  }

  List<CompiledFunction> _codeSection() {
    final r = _code;
    if (r == null) {
      if (_declared.isEmpty) return const <CompiledFunction>[];
      _refuse(
        'the module declares ${_declared.length} functions and has no '
        'code for them',
      );
    }
    final count = r.u32();
    if (count != _declared.length) {
      _refuse(
        'the module declares ${_declared.length} functions and has '
        'code for $count',
      );
    }
    return <CompiledFunction>[
      for (var i = 0; i < count; i++)
        _Compiler(
          this,
          _imports.length + i,
          _functionTypes[_imports.length + i],
          r.section(r.u32()),
        ).compile(),
    ];
  }
}

const int _kindBlock = 0;
const int _kindLoop = 1;
const int _kindIf = 2;
const int _kindFunction = 3;

/// A value whose type nothing can tell, past an `unreachable`: it matches
/// whatever pops it.
const int _anyType = 0;

/// One open block while a body is compiled.
final class _Frame {
  _Frame(this.kind, this.height, this.resultType, this.start);

  final int kind;

  /// The operand stack's height when the block was entered.
  final int height;

  /// The type of the value the block leaves, or null for none.
  final int? resultType;

  /// Where a branch to a loop goes: its first instruction.
  final int start;

  bool unreachable = false;

  /// Branch targets waiting for the slot after this block's end.
  final List<int> pending = <int>[];

  int ifAt = -1;
  int elseAt = -1;

  /// How many values the block leaves: nought or one.
  int get arity => resultType == null ? 0 : 1;

  /// What a branch to this block carries: a loop's branch goes back to its
  /// start and carries nothing.
  int get branchArity => kind == _kindLoop ? 0 : arity;

  /// The type a branch to this block carries, or null.
  int? get branchType => kind == _kindLoop ? null : resultType;
}

/// Validates one body and flattens it into jumps.
///
/// **Typing is following the operand stack.** A step module holds nothing
/// but `i32`, so checking its body is counting; a render module holds `f32`
/// beside it, so each slot of the stack carries its type and every
/// instruction checks the types it pops. An instruction that pops more than
/// its block holds or a value of the wrong type, a block that ends with the
/// wrong values, a branch to a block that is not there — each is a refusal,
/// at load.
final class _Compiler {
  _Compiler(this._module, this._index, this._type, this._r);

  final _Decoder _module;
  final int _index;
  final FunctionType _type;
  final _Reader _r;

  final List<int> _ops = <int>[];
  final List<int> _a = <int>[];
  final List<int> _b = <int>[];
  final List<int> _targets = <int>[];
  final List<_Frame> _frames = <_Frame>[];

  /// The type of each value on the operand stack.
  final List<int> _stack = <int>[];
  int _maxHeight = 0;
  final List<int> _locals = <int>[];

  String get _where => 'function $_index';

  bool get _floats => _module.floats;

  CompiledFunction compile() {
    _locals.addAll(_type.paramTypes);
    for (var i = _r.u32(); i > 0; i--) {
      final count = _r.u32();
      final type = _module.valueType(_r.byte(), '$_where\'s locals');
      if (_locals.length + count > 50000) {
        _refuse('$_where declares over 50000 locals');
      }
      for (var l = 0; l < count; l++) {
        _locals.add(type);
      }
    }
    _frames.add(_Frame(_kindFunction, 0, _type.resultTypes.firstOrNull, 0));
    while (_frames.isNotEmpty) {
      _instruction(_r.byte());
    }
    if (!_r.atEnd) _refuse('$_where has instructions after its end');
    return CompiledFunction(
      type: _type,
      localCount: _locals.length,
      maxHeight: _maxHeight,
      ops: List<int>.unmodifiable(_ops),
      a: List<int>.unmodifiable(_a),
      b: List<int>.unmodifiable(_b),
      targets: List<int>.unmodifiable(_targets),
    );
  }

  int _emit(int op, [int a = 0, int b = 0]) {
    _ops.add(op);
    _a.add(a);
    _b.add(b);
    return _ops.length - 1;
  }

  void _push(int type) {
    _stack.add(type);
    if (_stack.length > _maxHeight) _maxHeight = _stack.length;
  }

  /// Pops one value for [what], of [type] (any when null), and answers the
  /// type it had.
  int _pop(String what, [int? type = typeI32]) {
    final frame = _frames.last;
    if (_stack.length == frame.height) {
      if (frame.unreachable) return type ?? _anyType;
      _refuse('$_where: $what needs a value and its block has none left');
    }
    final found = _stack.removeLast();
    if (type != null && found != _anyType && found != type) {
      _refuse(
        '$_where: $what takes an ${_typeName(type)} and is handed an '
        '${_typeName(found)}',
      );
    }
    return found;
  }

  void _popAll(String what, List<int> types) {
    for (final type in types.reversed) {
      _pop(what, type);
    }
  }

  void _unreachable() {
    final frame = _frames.last..unreachable = true;
    _stack.length = frame.height;
  }

  _Frame _label(int depth) {
    if (depth >= _frames.length) {
      _refuse(
        '$_where branches out $depth blocks, and is inside '
        '${_frames.length}',
      );
    }
    return _frames[_frames.length - 1 - depth];
  }

  int _target(_Frame frame) {
    final index = _targets.length ~/ 3;
    final arity = frame.branchArity;
    _targets.addAll(<int>[
      if (frame.kind == _kindLoop) frame.start else -1,
      arity,
      frame.height + arity,
    ]);
    if (frame.kind != _kindLoop) frame.pending.add(index);
    return index;
  }

  /// The type a block yields, or null for none.
  int? _blockType() {
    final type = _r.peek();
    if (type == 0x40) {
      _r.byte();
      return null;
    }
    if (type == 0x7F ||
        type == 0x7E ||
        type == 0x7D ||
        type == 0x7C ||
        type == 0x7B ||
        type == 0x70 ||
        type == 0x6F) {
      _r.byte();
      return _module.valueType(type, '$_where\'s block');
    }
    _refuse(
      '$_where has a block typed by index; ABI $wasmPluginAbi blocks '
      'yield nothing or one value',
    );
  }

  void _memory(String what) {
    if (_module._memoryMin == null) {
      _refuse('$_where uses $what and the module has no memory');
    }
  }

  int _memarg(int natural, String what) {
    _memory(what);
    final align = _r.u32();
    if (align > natural) {
      _refuse('$_where aligns $what to 2^$align, past its natural 2^$natural');
    }
    return _r.u32();
  }

  void _end() {
    final frame = _frames.last;
    if (frame.resultType case final type?) _pop('the block\'s end', type);
    if (!frame.unreachable && _stack.length != frame.height) {
      _refuse(
        '$_where ends a block with '
        '${_stack.length - frame.height + frame.arity} values '
        'where it yields ${frame.arity}',
      );
    }
    if (frame.kind == _kindIf && frame.elseAt < 0 && frame.arity > 0) {
      _refuse('$_where has an if that yields a value and no else');
    }
    final end = frame.kind == _kindFunction ? _emit(opReturn) : _ops.length;
    for (final index in frame.pending) {
      _targets[index * 3] = end;
    }
    if (frame.kind == _kindIf) {
      if (frame.elseAt >= 0) {
        _a[frame.elseAt] = end;
      } else {
        _a[frame.ifAt] = end;
      }
    }
    _frames.removeLast();
    _stack.length = frame.height;
    if (frame.resultType case final type?) _push(type);
  }

  /// One instruction of [types] in and [result] out, emitted as [op].
  void _typed(int op, List<int> types, int? result, {bool emit = true}) {
    _popAll(_hex(op), types);
    if (result != null) _push(result);
    if (emit) _emit(op);
  }

  void _instruction(int op) {
    switch (op) {
      case 0x00:
        _emit(opUnreachable);
        _unreachable();
      case 0x01:
        break;
      case 0x02:
        _frames.add(_Frame(_kindBlock, _stack.length, _blockType(), 0));
      case 0x03:
        _frames.add(
          _Frame(_kindLoop, _stack.length, _blockType(), _ops.length),
        );
      case 0x04:
        final type = _blockType();
        _pop('if');
        _frames.add(
          _Frame(_kindIf, _stack.length, type, 0)..ifAt = _emit(opIf),
        );
      case 0x05:
        final frame = _frames.last;
        if (frame.kind != _kindIf || frame.elseAt >= 0) {
          _refuse('$_where has an else that follows no if');
        }
        if (frame.resultType case final type?) {
          _pop('the if\'s first branch', type);
        }
        if (!frame.unreachable && _stack.length != frame.height) {
          _refuse(
            '$_where ends an if\'s first branch with '
            '${_stack.length - frame.height + frame.arity} values where it '
            'yields ${frame.arity}',
          );
        }
        frame
          ..elseAt = _emit(opElse)
          ..unreachable = false;
        _a[frame.ifAt] = _ops.length;
        _stack.length = frame.height;
      case 0x0B:
        _end();
      case 0x0C:
        final frame = _label(_r.u32());
        if (frame.branchType case final type?) _pop('br', type);
        _emit(opBr, _target(frame));
        _unreachable();
      case 0x0D:
        final frame = _label(_r.u32());
        _pop('br_if');
        if (frame.branchType case final type?) {
          _pop('br_if', type);
          _push(type);
        }
        _emit(opBrIf, _target(frame));
      case 0x0E:
        final count = _r.u32();
        if (count > 65536) _refuse('$_where has a br_table of $count');
        final depths = <int>[for (var i = 0; i <= count; i++) _r.u32()];
        _pop('br_table');
        final frames = <_Frame>[for (final depth in depths) _label(depth)];
        final type = frames.last.branchType;
        if (frames.any((_Frame f) => f.branchType != type)) {
          _refuse(
            '$_where has a br_table whose targets carry different '
            'values',
          );
        }
        if (type != null) _pop('br_table', type);
        final first = _targets.length ~/ 3;
        for (final frame in frames) {
          _target(frame);
        }
        _emit(opBrTable, first, count);
        _unreachable();
      case 0x0F:
        _popAll('return', _type.resultTypes);
        _emit(opReturn);
        _unreachable();
      case 0x10:
        final callee = _module._function(_r.u32(), _where);
        final type = _module._functionTypes[callee];
        _popAll('call', type.paramTypes);
        for (final result in type.resultTypes) {
          _push(result);
        }
        _emit(opCall, callee);
      case 0x11:
        _refuse(
          '$_where uses call_indirect (0x11); tables are not in ABI '
          '$wasmPluginAbi',
        );
      case 0x1A:
        _pop('drop', null);
        _emit(opDrop);
      case 0x1B:
        _pop('select');
        final second = _pop('select', null);
        final first = _pop('select', second == _anyType ? null : second);
        _push(first == _anyType ? second : first);
        _emit(opSelect);
      case 0x1C:
        final count = _r.u32();
        if (count != 1) _refuse('$_where has a select of $count types');
        final type = _module.valueType(_r.byte(), '$_where\'s select');
        _pop('select');
        _pop('select', type);
        _pop('select', type);
        _push(type);
        _emit(opSelect);
      case 0x20 || 0x21 || 0x22:
        final index = _r.u32();
        if (index >= _locals.length) {
          _refuse('$_where reads local $index, and has ${_locals.length}');
        }
        final type = _locals[index];
        if (op != 0x20) _pop('local.set', type);
        if (op != 0x21) _push(type);
        _emit(op, index);
      case 0x23 || 0x24:
        final index = _r.u32();
        if (index >= _module._globals.length) {
          _refuse(
            '$_where reads global $index, and the module has '
            '${_module._globals.length}',
          );
        }
        final global = _module._globals[index];
        if (op == 0x24) {
          if (!global.mutable) {
            _refuse('$_where sets global $index, which is immutable');
          }
          _pop('global.set', global.type);
        } else {
          _push(global.type);
        }
        _emit(op, index);
      case 0x28:
        final offset = _memarg(2, 'i32.load');
        _pop('i32.load');
        _push(typeI32);
        _emit(op, offset);
      case 0x2A when _floats:
        // f32.load: the four bytes as an i32's, which is what an f32 is here.
        final offset = _memarg(2, 'f32.load');
        _pop('f32.load');
        _push(typeF32);
        _emit(opLoad, offset);
      case 0x2C || 0x2D:
        final offset = _memarg(0, 'i32.load8');
        _pop('i32.load8');
        _push(typeI32);
        _emit(op, offset);
      case 0x2E || 0x2F:
        final offset = _memarg(1, 'i32.load16');
        _pop('i32.load16');
        _push(typeI32);
        _emit(op, offset);
      case 0x36:
        _emit(op, _memarg(2, 'i32.store'));
        _pop('i32.store');
        _pop('i32.store');
      case 0x38 when _floats:
        _emit(opStore, _memarg(2, 'f32.store'));
        _pop('f32.store', typeF32);
        _pop('f32.store');
      case 0x3A:
        _emit(op, _memarg(0, 'i32.store8'));
        _pop('i32.store8');
        _pop('i32.store8');
      case 0x3B:
        _emit(op, _memarg(1, 'i32.store16'));
        _pop('i32.store16');
        _pop('i32.store16');
      case 0x3F || 0x40:
        _memory(op == 0x3F ? 'memory.size' : 'memory.grow');
        if (_r.byte() != 0) _refuse('$_where names a second memory');
        if (op == 0x40) _pop('memory.grow');
        _push(typeI32);
        _emit(op);
      case 0x41:
        _push(typeI32);
        _emit(op, _r.s32());
      case 0x43 when _floats:
        _push(typeF32);
        _emit(opConst, _r.bits32());
      case 0x45 || 0x67 || 0x68 || 0x69 || 0xC0 || 0xC1:
        _typed(op, const <int>[typeI32], typeI32);
      case (>= 0x46 && <= 0x4F) || (>= 0x6A && <= 0x78):
        _typed(op, const <int>[typeI32, typeI32], typeI32);
      case >= 0x5B && <= 0x60 when _floats:
        // The f32 comparisons, each answering an i32.
        _typed(op, const <int>[typeF32, typeF32], typeI32);
      case >= 0x8B && <= 0x91 when _floats:
        // abs, neg, ceil, floor, trunc, nearest, sqrt.
        _typed(op, const <int>[typeF32], typeF32);
      case >= 0x92 && <= 0x98 when _floats:
        // add, sub, mul, div, min, max, copysign.
        _typed(op, const <int>[typeF32, typeF32], typeF32);
      case (0xA8 || 0xA9) when _floats:
        // i32.trunc_f32_s and _u, which trap on a value no i32 holds.
        _typed(op, const <int>[typeF32], typeI32);
      case (0xB2 || 0xB3) when _floats:
        // f32.convert_i32_s and _u.
        _typed(op, const <int>[typeI32], typeF32);
      case 0xBC when _floats:
        // i32.reinterpret_f32: the bits are already an i32's.
        _typed(op, const <int>[typeF32], typeI32, emit: false);
      case 0xBE when _floats:
        // f32.reinterpret_i32.
        _typed(op, const <int>[typeI32], typeF32, emit: false);
      case 0xFC:
        _refuse(
          '$_where uses a 0xFC-prefixed instruction (saturating '
          'truncation or bulk memory), which is not in ABI '
          '$wasmPluginAbi',
        );
      case (>= 0x29 && <= 0x35) ||
          (>= 0x37 && <= 0x3E) ||
          (>= 0x42 && <= 0x44) ||
          (>= 0x50 && <= 0x66) ||
          (>= 0x79 && <= 0xBF) ||
          (>= 0xC2 && <= 0xC4):
        _refuse(_module._onlyOurs('$_where uses instruction ${_hex(op)}'));
      default:
        _refuse(
          '$_where uses instruction ${_hex(op)}, which ABI '
          '$wasmPluginAbi does not have',
        );
    }
  }
}
