import 'dart:convert';
import 'dart:typed_data';

import 'abi.dart';

// The instructions a compiled body is made of. Most keep the opcode Wasm
// gives them; `block`, `loop` and `end` are gone, resolved into the jumps of
// `br`, `br_if`, `br_table`, `if` and `else`, and a function's last `end` is
// a `return`.
const int opUnreachable = 0x00;
const int opIf = 0x04;
const int opElse = 0x05;
const int opBr = 0x0C;
const int opBrIf = 0x0D;
const int opBrTable = 0x0E;
const int opReturn = 0x0F;
const int opCall = 0x10;
const int opDrop = 0x1A;
const int opSelect = 0x1B;
const int opLocalGet = 0x20;
const int opLocalSet = 0x21;
const int opLocalTee = 0x22;
const int opGlobalGet = 0x23;
const int opGlobalSet = 0x24;
const int opLoad = 0x28;
const int opLoad8S = 0x2C;
const int opLoad8U = 0x2D;
const int opLoad16S = 0x2E;
const int opLoad16U = 0x2F;
const int opStore = 0x36;
const int opStore8 = 0x3A;
const int opStore16 = 0x3B;
const int opMemorySize = 0x3F;
const int opMemoryGrow = 0x40;
const int opConst = 0x41;

// The host functions an import may name, by what the interpreter calls.
const int hostFieldLen = 0;
const int hostFieldGet = 1;
const int hostFieldSet = 2;
const int hostPublish = 3;
const int hostFieldFrac = 4;

/// The host functions a module may import: name, then the host function,
/// parameter and result counts. Which ABI each arrived in is
/// `wasmImportSince`; whether a module may use it is checked against the
/// ABI it says, at instantiation.
const Map<String, (int, int, int)> _abiImports = <String, (int, int, int)>{
  'field_len': (hostFieldLen, 1, 1),
  'field_get': (hostFieldGet, 2, 1),
  'field_set': (hostFieldSet, 3, 0),
  'publish': (hostPublish, 3, 0),
  'field_frac': (hostFieldFrac, 1, 1),
};

/// A function's signature. Every value is an `i32`, so a count says it all.
final class FunctionType {
  const FunctionType(this.params, this.results);

  final int params;
  final int results;

  @override
  bool operator ==(Object other) =>
      other is FunctionType &&
      other.params == params &&
      other.results == results;

  @override
  int get hashCode => Object.hash(params, results);
}

/// One function body, validated and flattened into jumps.
///
/// [ops] holds an instruction per slot; [a] and [b] its immediates. A branch
/// names an entry of [targets], three numbers each: the slot to go to, how
/// many values it carries (nought or one), and the operand stack's height
/// after it — all worked out at decode, so a branch at run time is two
/// assignments.
final class CompiledFunction {
  const CompiledFunction({
    required this.type,
    required this.localCount,
    required this.maxHeight,
    required this.ops,
    required this.a,
    required this.b,
    required this.targets,
  });

  final FunctionType type;

  /// Parameters and declared locals together.
  final int localCount;

  /// The deepest the operand stack gets.
  final int maxHeight;

  final List<int> ops;
  final List<int> a;
  final List<int> b;
  final List<int> targets;
}

/// A global's starting value and whether it may change.
final class ModuleGlobal {
  const ModuleGlobal({required this.mutable, required this.init});

  final bool mutable;
  final int init;
}

/// Bytes copied into memory at instantiation.
final class DataSegment {
  const DataSegment(this.offset, this.bytes);

  final int offset;
  final Uint8List bytes;
}

/// A Wasm module that is ABI 1: decoded, validated and compiled, ready for
/// any [WasmRuntime].
///
/// **Refused at load, not at the first step.** [decode] reads every section
/// and every instruction before it answers, so a module that uses a 64-bit
/// value, imports something ABI 1 does not offer or branches out of its own
/// body never gets as far as an engine. Each refusal names what it found and
/// where. The browser runtime runs this check too, so the same bytes are
/// refused everywhere.
final class WasmModule {
  WasmModule._({
    required this.bytes,
    required this.functionTypes,
    required this.imports,
    required this.importNames,
    required this.functions,
    required this.memoryMin,
    required this.memoryMax,
    required this.globals,
    required this.functionExports,
    required this.globalExports,
    required this.memoryExport,
    required this.start,
    required this.data,
  });

  /// The bytes it was decoded from, for a runtime that compiles them itself.
  final Uint8List bytes;

  /// Every function's signature by function index: the imports first.
  final List<FunctionType> functionTypes;

  /// The host function behind each imported function, by function index.
  final List<int> imports;

  /// The name of each imported function, by function index — what the
  /// module asks the host for, checked against its ABI when it starts.
  final List<String> importNames;

  /// The module's own functions, from function index `imports.length` on.
  final List<CompiledFunction> functions;

  /// The memory's starting pages, or null for a module with no memory.
  final int? memoryMin;

  /// The most pages the module says its memory may grow to, if it says.
  final int? memoryMax;

  final List<ModuleGlobal> globals;

  /// Exported functions, by export name.
  final Map<String, int> functionExports;

  /// Exported globals, by export name.
  final Map<String, int> globalExports;

  /// The name the memory is exported under, if it is.
  final String? memoryExport;

  /// The start function's index, if there is one.
  final int? start;

  final List<DataSegment> data;

  /// `f3d_abi`'s function index.
  int get abiFunction => functionExports['f3d_abi']!;

  /// `f3d_step`'s function index.
  int get stepFunction => functionExports['f3d_step']!;

  /// Reads and checks [bytes]. Throws [WasmException] with a sentence naming
  /// the section, the instruction or the import that is not ABI 1.
  static WasmModule decode(Uint8List bytes) => _Decoder(bytes).decode();
}

Never _refuse(String message) => throw WasmException(message);

String _hex(int value) => '0x${value.toRadixString(16).padLeft(2, '0')}';

String _abiOnlyI32(String what) =>
    '$what: ABI $wasmPluginAbi is 32-bit integers only, so one module gives '
    'one answer on the VM, in a browser and on a server';

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

/// Reads one value type, refusing every one but `i32` with the reason.
void _valueType(int type, String where) {
  switch (type) {
    case 0x7F:
      return;
    case 0x7E:
      _refuse(_abiOnlyI32('$where uses an i64'));
    case 0x7D:
      _refuse(_abiOnlyI32('$where uses an f32'));
    case 0x7C:
      _refuse(_abiOnlyI32('$where uses an f64'));
    case 0x7B:
      _refuse(_abiOnlyI32('$where uses a v128'));
    case 0x70 || 0x6F:
      _refuse(
        '$where uses a reference type; references and tables are not '
        'in ABI $wasmPluginAbi',
      );
    default:
      _refuse('$where names value type ${_hex(type)}, which is not Wasm');
  }
}

final class _Decoder {
  _Decoder(this.bytes);

  final Uint8List bytes;

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
        case 12:
          break; // the data count, which only bulk memory needs
        default:
          _refuse('section $id is not a Wasm section');
      }
    }
    final functions = _codeSection();
    _checkExports();
    final start = _start;
    if (start != null && _functionTypes[start] != const FunctionType(0, 0)) {
      _refuse(
        'the start function takes or returns values; it must take '
        'none and return none',
      );
    }
    return WasmModule._(
      bytes: bytes,
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
      final params = r.u32();
      for (var p = 0; p < params; p++) {
        _valueType(r.byte(), 'type ${_types.length}');
      }
      final results = r.u32();
      for (var p = 0; p < results; p++) {
        _valueType(r.byte(), 'type ${_types.length}');
      }
      if (results > 1) {
        _refuse(
          'type ${_types.length} returns $results values; a function '
          'returns at most one in ABI $wasmPluginAbi',
        );
      }
      _types.add(FunctionType(params, results));
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
      final abi = _abiImports[name];
      if (module != 'f3d' || abi == null) {
        _refuse(
          '$what is not one ABI $wasmPluginAbi offers. A module '
          'imports f3d.field_len, f3d.field_get, f3d.field_set, '
          'f3d.publish and f3d.field_frac, and nothing else: there is no '
          'file, clock or network to reach',
        );
      }
      final (host, params, results) = abi;
      if (type != FunctionType(params, results)) {
        _refuse(
          '$what takes ${type.params} and returns ${type.results}; '
          'ABI $wasmPluginAbi has it take $params and return $results',
        );
      }
      _imports.add(host);
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

  int _constant(_Reader r, String where) {
    if (r.byte() != opConst) {
      _refuse(
        '$where does not start from i32.const; in ABI $wasmPluginAbi '
        'it must',
      );
    }
    final value = r.s32();
    if (r.byte() != 0x0B) {
      _refuse(
        '$where is more than one i32.const; in ABI $wasmPluginAbi it '
        'is one',
      );
    }
    return value;
  }

  void _globalSection(_Reader r) {
    for (var i = r.u32(); i > 0; i--) {
      final where = 'global ${_globals.length}';
      _valueType(r.byte(), where);
      final mutable = switch (r.byte()) {
        0 => false,
        1 => true,
        _ => _refuse('$where is neither mutable nor immutable'),
      };
      _globals.add(ModuleGlobal(mutable: mutable, init: _constant(r, where)));
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
    if (_functionTypes[abi] != const FunctionType(0, 1)) {
      _refuse('f3d_abi must take nothing and return an i32');
    }
    final step = _functionExports['f3d_step'];
    if (step == null) {
      _refuse(
        'the module exports no f3d_step(i32 step, i32 dt), so there '
        'is nothing to run each step',
      );
    }
    if (_functionTypes[step] != const FunctionType(2, 0)) {
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

/// One open block while a body is compiled.
final class _Frame {
  _Frame(this.kind, this.height, this.arity, this.start);

  final int kind;

  /// The operand stack's height when the block was entered.
  final int height;

  /// How many values the block leaves: nought or one.
  final int arity;

  /// Where a branch to a loop goes: its first instruction.
  final int start;

  bool unreachable = false;

  /// Branch targets waiting for the slot after this block's end.
  final List<int> pending = <int>[];

  int ifAt = -1;
  int elseAt = -1;

  /// What a branch to this block carries: a loop's branch goes back to its
  /// start and carries nothing.
  int get branchArity => kind == _kindLoop ? 0 : arity;
}

/// Validates one body and flattens it into jumps.
///
/// **Typing is counting.** Every value in ABI 1 is an `i32`, so checking a
/// body is following the operand stack's height through it: an instruction
/// that pops more than its block holds, a block that ends with the wrong
/// number of values, a branch to a block that is not there — each is a
/// refusal, at load.
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
  int _height = 0;
  int _maxHeight = 0;
  int _localCount = 0;

  String get _where => 'function $_index';

  CompiledFunction compile() {
    _localCount = _type.params;
    for (var i = _r.u32(); i > 0; i--) {
      final count = _r.u32();
      _valueType(_r.byte(), '$_where\'s locals');
      _localCount += count;
      if (_localCount > 50000) _refuse('$_where declares over 50000 locals');
    }
    _frames.add(_Frame(_kindFunction, 0, _type.results, 0));
    while (_frames.isNotEmpty) {
      _instruction(_r.byte());
    }
    if (!_r.atEnd) _refuse('$_where has instructions after its end');
    return CompiledFunction(
      type: _type,
      localCount: _localCount,
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

  void _push([int count = 1]) {
    _height += count;
    if (_height > _maxHeight) _maxHeight = _height;
  }

  void _pop(String what, [int count = 1]) {
    final frame = _frames.last;
    for (var i = 0; i < count; i++) {
      if (_height == frame.height) {
        if (frame.unreachable) return;
        _refuse('$_where: $what needs a value and its block has none left');
      }
      _height--;
    }
  }

  void _unreachable() {
    final frame = _frames.last..unreachable = true;
    _height = frame.height;
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

  int _blockType() {
    final type = _r.peek();
    if (type == 0x40) {
      _r.byte();
      return 0;
    }
    if (type == 0x7F ||
        type == 0x7E ||
        type == 0x7D ||
        type == 0x7C ||
        type == 0x7B ||
        type == 0x70 ||
        type == 0x6F) {
      _r.byte();
      _valueType(type, '$_where\'s block');
      return 1;
    }
    _refuse(
      '$_where has a block typed by index; ABI $wasmPluginAbi blocks '
      'yield nothing or one i32',
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
    if (!frame.unreachable && _height != frame.height + frame.arity) {
      _refuse(
        '$_where ends a block with ${_height - frame.height} values '
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
    _height = frame.height + frame.arity;
  }

  void _instruction(int op) {
    switch (op) {
      case 0x00:
        _emit(opUnreachable);
        _unreachable();
      case 0x01:
        break;
      case 0x02:
        _frames.add(_Frame(_kindBlock, _height, _blockType(), 0));
      case 0x03:
        _frames.add(_Frame(_kindLoop, _height, _blockType(), _ops.length));
      case 0x04:
        final arity = _blockType();
        _pop('if');
        _frames.add(_Frame(_kindIf, _height, arity, 0)..ifAt = _emit(opIf));
      case 0x05:
        final frame = _frames.last;
        if (frame.kind != _kindIf || frame.elseAt >= 0) {
          _refuse('$_where has an else that follows no if');
        }
        if (!frame.unreachable && _height != frame.height + frame.arity) {
          _refuse(
            '$_where ends an if\'s first branch with '
            '${_height - frame.height} values where it yields '
            '${frame.arity}',
          );
        }
        frame
          ..elseAt = _emit(opElse)
          ..unreachable = false;
        _a[frame.ifAt] = _ops.length;
        _height = frame.height;
      case 0x0B:
        _end();
      case 0x0C:
        final frame = _label(_r.u32());
        _pop('br', frame.branchArity);
        _emit(opBr, _target(frame));
        _unreachable();
      case 0x0D:
        final frame = _label(_r.u32());
        _pop('br_if');
        _pop('br_if', frame.branchArity);
        _push(frame.branchArity);
        _emit(opBrIf, _target(frame));
      case 0x0E:
        final count = _r.u32();
        if (count > 65536) _refuse('$_where has a br_table of $count');
        final depths = <int>[for (var i = 0; i <= count; i++) _r.u32()];
        _pop('br_table');
        final frames = <_Frame>[for (final depth in depths) _label(depth)];
        final arity = frames.last.branchArity;
        if (frames.any((_Frame f) => f.branchArity != arity)) {
          _refuse(
            '$_where has a br_table whose targets carry different '
            'numbers of values',
          );
        }
        _pop('br_table', arity);
        final first = _targets.length ~/ 3;
        for (final frame in frames) {
          _target(frame);
        }
        _emit(opBrTable, first, count);
        _unreachable();
      case 0x0F:
        _pop('return', _type.results);
        _emit(opReturn);
        _unreachable();
      case 0x10:
        final callee = _module._function(_r.u32(), _where);
        final type = _module._functionTypes[callee];
        _pop('call', type.params);
        _push(type.results);
        _emit(opCall, callee);
      case 0x11:
        _refuse(
          '$_where uses call_indirect (0x11); tables are not in ABI '
          '$wasmPluginAbi',
        );
      case 0x1A:
        _pop('drop');
        _emit(opDrop);
      case 0x1B:
        _pop('select', 3);
        _push();
        _emit(opSelect);
      case 0x1C:
        final count = _r.u32();
        if (count != 1) _refuse('$_where has a select of $count types');
        _valueType(_r.byte(), '$_where\'s select');
        _pop('select', 3);
        _push();
        _emit(opSelect);
      case 0x20 || 0x21 || 0x22:
        final index = _r.u32();
        if (index >= _localCount) {
          _refuse('$_where reads local $index, and has $_localCount');
        }
        if (op != 0x20) _pop('local.set');
        if (op != 0x21) _push();
        _emit(op, index);
      case 0x23 || 0x24:
        final index = _r.u32();
        if (index >= _module._globals.length) {
          _refuse(
            '$_where reads global $index, and the module has '
            '${_module._globals.length}',
          );
        }
        if (op == 0x24) {
          if (!_module._globals[index].mutable) {
            _refuse('$_where sets global $index, which is immutable');
          }
          _pop('global.set');
        } else {
          _push();
        }
        _emit(op, index);
      case 0x28:
        final offset = _memarg(2, 'i32.load');
        _pop('i32.load');
        _push();
        _emit(op, offset);
      case 0x2C || 0x2D:
        final offset = _memarg(0, 'i32.load8');
        _pop('i32.load8');
        _push();
        _emit(op, offset);
      case 0x2E || 0x2F:
        final offset = _memarg(1, 'i32.load16');
        _pop('i32.load16');
        _push();
        _emit(op, offset);
      case 0x36:
        _emit(op, _memarg(2, 'i32.store'));
        _pop('i32.store', 2);
      case 0x3A:
        _emit(op, _memarg(0, 'i32.store8'));
        _pop('i32.store8', 2);
      case 0x3B:
        _emit(op, _memarg(1, 'i32.store16'));
        _pop('i32.store16', 2);
      case 0x3F || 0x40:
        _memory(op == 0x3F ? 'memory.size' : 'memory.grow');
        if (_r.byte() != 0) _refuse('$_where names a second memory');
        if (op == 0x40) _pop('memory.grow');
        _push();
        _emit(op);
      case 0x41:
        _push();
        _emit(op, _r.s32());
      case 0x45 || 0x67 || 0x68 || 0x69 || 0xC0 || 0xC1:
        _pop(_hex(op));
        _push();
        _emit(op);
      case >= 0x46 && <= 0x4F:
        _pop(_hex(op), 2);
        _push();
        _emit(op);
      case >= 0x6A && <= 0x78:
        _pop(_hex(op), 2);
        _push();
        _emit(op);
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
        _refuse(_abiOnlyI32('$_where uses instruction ${_hex(op)}'));
      default:
        _refuse(
          '$_where uses instruction ${_hex(op)}, which ABI '
          '$wasmPluginAbi does not have',
        );
    }
  }
}
