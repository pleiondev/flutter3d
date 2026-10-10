import 'dart:convert';
import 'dart:typed_data';

import 'abi.dart';
import 'i32.dart';
import 'module.dart';

const int _pageBytes = 65536;

/// Runs an ABI 1 module in plain Dart, the same way on every platform.
///
/// **The runtime a replay is held to.** It counts every instruction against
/// [WasmLimits.fuelPerStep] and every call against [WasmLimits.callDepth], so
/// a module that runs away stops at the same instruction on a phone, in a
/// browser and on the server that replays the run. Its arithmetic is the
/// written-out 32-bit arithmetic of `i32.dart`, which keeps every
/// intermediate under 2^53, so a browser — where an `int` is a double — gives
/// the bits the VM gives.
///
/// **Small because ABI 1 is small.** One value type, one memory, no tables,
/// no floats: decode has already resolved every branch to a jump, so what is
/// left here is a loop over flat instructions.
final class WasmInterpreter extends WasmRuntime {
  const WasmInterpreter();

  @override
  String get name => 'interpreter';

  @override
  bool get isMetered => true;

  @override
  WasmInstance instantiate(
    WasmModule module,
    WasmImports imports,
    WasmLimits limits,
  ) => _Instance(module, imports, limits).._begin();
}

final class _Instance extends WasmInstance {
  _Instance(this._module, this._imports, this._limits)
    : _globals = <int>[for (final g in _module.globals) g.init] {
    final min = _module.memoryMin;
    if (min != null) {
      if (min > _limits.memoryPages) {
        throw WasmException(
          'the module\'s memory starts at $min pages and this plugin may '
          'have ${_limits.memoryPages}',
        );
      }
      final max = _module.memoryMax;
      _maxPages = max == null || max > _limits.memoryPages
          ? _limits.memoryPages
          : max;
      _setMemory(min);
      for (final segment in _module.data) {
        if (segment.offset + segment.bytes.length > _memory.length) {
          throw WasmException(
            'a data segment at ${segment.offset} runs past the memory\'s '
            '${_memory.length} bytes',
          );
        }
        _memory.setRange(
          segment.offset,
          segment.offset + segment.bytes.length,
          segment.bytes,
        );
      }
    }
  }

  final WasmModule _module;
  final WasmImports _imports;
  final WasmLimits _limits;
  final List<int> _globals;

  Uint8List _memory = Uint8List(0);
  ByteData _view = ByteData(0);
  int _pages = 0;
  int _maxPages = 0;
  int _fuel = 0;
  int _used = 0;

  @override
  int get fuelUsed => _used;

  int _abi = wasmPluginAbiMin;

  @override
  int get abi => _abi;

  void _setMemory(int pages) {
    final next = Uint8List(pages * _pageBytes)
      ..setRange(0, _memory.length, _memory);
    _memory = next;
    _view = ByteData.sublistView(next);
    _pages = pages;
  }

  void _begin() {
    final start = _module.start;
    if (start != null) _run(start, const <int>[]);
    final abi = _run(_module.abiFunction, const <int>[]);
    final refusal = wasmAbiRefusal(abi, _module.importNames);
    if (refusal != null) throw WasmException(refusal);
    _abi = abi;
    _used = 0;
  }

  int _run(int function, List<int> args) {
    _fuel = _limits.fuelPerStep;
    try {
      return _invoke(function, args, 0);
    } finally {
      _used = _limits.fuelPerStep - (_fuel < 0 ? 0 : _fuel);
    }
  }

  @override
  void step(int step, int dtFixed) =>
      _run(_module.stepFunction, <int>[i32(step), i32(dtFixed)]);

  int _host(int host, List<int> args) {
    switch (host) {
      case hostFieldLen:
        return i32(_imports.fieldLength(args[0]));
      case hostFieldGet:
        return i32(_imports.fieldGet(args[0], args[1]));
      case hostFieldSet:
        _imports.fieldSet(args[0], args[1], args[2]);
        return 0;
      case hostFieldFrac:
        return i32(_imports.fieldFractionBits(args[0]));
      default:
        _imports.publish(args[0], args[1], args[2]);
        return 0;
    }
  }

  int _address(int base, int offset, int size) {
    final at = u32(base) + offset;
    if (at + size > _memory.length) {
      throw WasmTrapException(
        'the module reached $size bytes at $at, past its memory\'s '
        '${_memory.length}',
      );
    }
    return at;
  }

  /// Calls function [index] with [args]; returns its result, or nought for a
  /// function that returns none.
  int _invoke(int index, List<int> args, int depth) {
    final imported = _module.imports.length;
    if (index < imported) return _host(_module.imports[index], args);
    if (depth >= _limits.callDepth) {
      throw WasmTrapException(
        'calls nested deeper than ${_limits.callDepth} in one step',
      );
    }
    final f = _module.functions[index - imported];
    final locals = List<int>.filled(f.localCount, 0);
    for (var i = 0; i < args.length; i++) {
      locals[i] = args[i];
    }
    final stack = List<int>.filled(f.maxHeight + 1, 0);
    final ops = f.ops;
    final a = f.a;
    final b = f.b;
    final targets = f.targets;
    var sp = 0;
    var pc = 0;

    // A branch: keep the value it carries, cut the stack to the label's
    // height, go. Decode worked out all three.
    void branch(int target) {
      final t = target * 3;
      final height = targets[t + 2];
      if (targets[t + 1] == 1) stack[height - 1] = stack[sp - 1];
      sp = height;
      pc = targets[t];
    }

    while (true) {
      if (--_fuel < 0) {
        throw WasmTrapException(
          'the module ran out of fuel (${_limits.fuelPerStep} instructions '
          'per step)',
        );
      }
      final op = ops[pc];
      switch (op) {
        case opUnreachable:
          throw const WasmTrapException('the module reached unreachable');
        case opIf:
          pc = stack[--sp] == 0 ? a[pc] : pc + 1;
        case opElse:
          pc = a[pc];
        case opBr:
          branch(a[pc]);
        case opBrIf:
          if (stack[--sp] != 0) {
            branch(a[pc]);
          } else {
            pc++;
          }
        case opBrTable:
          final chosen = u32(stack[--sp]);
          final count = b[pc];
          branch(a[pc] + (chosen < count ? chosen : count));
        case opReturn:
          return f.type.results == 1 ? stack[sp - 1] : 0;
        case opCall:
          final callee = a[pc];
          final type = _module.functionTypes[callee];
          final params = type.params;
          final callArgs = stack.sublist(sp - params, sp);
          sp -= params;
          final result = _invoke(callee, callArgs, depth + 1);
          if (type.results == 1) stack[sp++] = result;
          pc++;
        case opDrop:
          sp--;
          pc++;
        case opSelect:
          final condition = stack[--sp];
          final second = stack[--sp];
          if (condition == 0) stack[sp - 1] = second;
          pc++;
        case opLocalGet:
          stack[sp++] = locals[a[pc]];
          pc++;
        case opLocalSet:
          locals[a[pc]] = stack[--sp];
          pc++;
        case opLocalTee:
          locals[a[pc]] = stack[sp - 1];
          pc++;
        case opGlobalGet:
          stack[sp++] = _globals[a[pc]];
          pc++;
        case opGlobalSet:
          _globals[a[pc]] = stack[--sp];
          pc++;
        case opLoad:
          stack[sp - 1] = _view.getInt32(
            _address(stack[sp - 1], a[pc], 4),
            Endian.little,
          );
          pc++;
        case opLoad8S:
          stack[sp - 1] = _view.getInt8(_address(stack[sp - 1], a[pc], 1));
          pc++;
        case opLoad8U:
          stack[sp - 1] = _view.getUint8(_address(stack[sp - 1], a[pc], 1));
          pc++;
        case opLoad16S:
          stack[sp - 1] = _view.getInt16(
            _address(stack[sp - 1], a[pc], 2),
            Endian.little,
          );
          pc++;
        case opLoad16U:
          stack[sp - 1] = _view.getUint16(
            _address(stack[sp - 1], a[pc], 2),
            Endian.little,
          );
          pc++;
        case opStore:
          final value = stack[--sp];
          _view.setInt32(
            _address(stack[--sp], a[pc], 4),
            i32(value),
            Endian.little,
          );
          pc++;
        case opStore8:
          final value = stack[--sp];
          _view.setUint8(_address(stack[--sp], a[pc], 1), value & 0xFF);
          pc++;
        case opStore16:
          final value = stack[--sp];
          _view.setUint16(
            _address(stack[--sp], a[pc], 2),
            value & 0xFFFF,
            Endian.little,
          );
          pc++;
        case opMemorySize:
          stack[sp++] = _pages;
          pc++;
        case opMemoryGrow:
          final delta = u32(stack[sp - 1]);
          final before = _pages;
          if (before + delta > _maxPages) {
            stack[sp - 1] = -1;
          } else {
            _setMemory(before + delta);
            stack[sp - 1] = before;
          }
          pc++;
        case opConst:
          stack[sp++] = a[pc];
          pc++;
        case 0x45:
          stack[sp - 1] = stack[sp - 1] == 0 ? 1 : 0;
          pc++;
        case 0x67:
          stack[sp - 1] = i32Clz(stack[sp - 1]);
          pc++;
        case 0x68:
          stack[sp - 1] = i32Ctz(stack[sp - 1]);
          pc++;
        case 0x69:
          stack[sp - 1] = i32Popcnt(stack[sp - 1]);
          pc++;
        case 0xC0:
          stack[sp - 1] = i32Extend8(stack[sp - 1]);
          pc++;
        case 0xC1:
          stack[sp - 1] = i32Extend16(stack[sp - 1]);
          pc++;
        default:
          final y = stack[--sp];
          final x = stack[sp - 1];
          stack[sp - 1] = _binary(op, x, y);
          pc++;
      }
    }
  }

  /// The two-operand instructions, 0x46–0x4F and 0x6A–0x78.
  static int _binary(int op, int x, int y) => switch (op) {
    0x46 => x == y ? 1 : 0,
    0x47 => x != y ? 1 : 0,
    0x48 => x < y ? 1 : 0,
    0x49 => u32(x) < u32(y) ? 1 : 0,
    0x4A => x > y ? 1 : 0,
    0x4B => u32(x) > u32(y) ? 1 : 0,
    0x4C => x <= y ? 1 : 0,
    0x4D => u32(x) <= u32(y) ? 1 : 0,
    0x4E => x >= y ? 1 : 0,
    0x4F => u32(x) >= u32(y) ? 1 : 0,
    0x6A => i32(x + y),
    0x6B => i32(x - y),
    0x6C => i32Mul(x, y),
    0x6D => _divS(x, y),
    0x6E => y == 0 ? _byZero() : i32(u32(x) ~/ u32(y)),
    0x6F => y == 0 ? _byZero() : (y == -1 ? 0 : x.remainder(y)),
    0x70 => y == 0 ? _byZero() : i32(u32(x) % u32(y)),
    0x71 => i32(x & y),
    0x72 => i32(x | y),
    0x73 => i32(x ^ y),
    0x74 => i32Shl(x, y),
    0x75 => i32ShrS(x, y),
    0x76 => i32ShrU(x, y),
    0x77 => i32Rotl(x, y),
    _ => i32Rotr(x, y),
  };

  static Never _byZero() =>
      throw const WasmTrapException('the module divided by nought');

  static int _divS(int x, int y) {
    if (y == 0) _byZero();
    if (x == -0x80000000 && y == -1) {
      throw const WasmTrapException(
        'the module divided -2^31 by -1, which overflows',
      );
    }
    return i32(x ~/ y);
  }

  @override
  Map<String, Object?> save() {
    var last = _memory.length;
    while (last > 0 && _memory[last - 1] == 0) {
      last--;
    }
    return <String, Object?>{
      'pages': _pages,
      // Up to the last byte that is not nought: a fresh megabyte of memory
      // is a few characters, not a megabyte of text.
      'memory': base64Encode(Uint8List.sublistView(_memory, 0, last)),
      'globals': List<int>.of(_globals),
    };
  }

  /// Puts back what [save] wrote.
  ///
  /// **Everything is checked before anything is replaced**: a state that is
  /// not this module's — pages out of range, memory that is not base64 or
  /// does not fit its pages, a global that is not a number — is refused
  /// with a [WasmFormatException] and the module is left as it was, rather
  /// than wiped and then thrown out of with somebody else's error.
  @override
  void restore(Map<String, Object?> state) {
    const refused = WasmFormatException('not the state of this Wasm module');
    final pages = state['pages'];
    final memory = state['memory'];
    final globals = state['globals'];
    if (pages is! int ||
        pages < 0 ||
        pages > _maxPages ||
        memory is! String ||
        globals is! List<Object?> ||
        globals.length != _globals.length ||
        globals.any((Object? g) => g is! int)) {
      throw refused;
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(memory);
    } on FormatException {
      throw refused;
    }
    if (bytes.length > pages * _pageBytes) throw refused;
    _memory = Uint8List(0);
    _setMemory(pages);
    _memory.setRange(0, bytes.length, bytes);
    _globals.setAll(0, globals.cast<int>());
  }
}
