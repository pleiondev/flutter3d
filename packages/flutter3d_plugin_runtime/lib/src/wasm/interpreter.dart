import 'dart:convert';
import 'dart:math' as math;
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
/// **Small because the ABI is small.** One memory, no tables, `i32` in a
/// step module and `f32` beside it in a render module, held as its bits:
/// decode has already resolved every branch to a jump and checked every
/// type, so what is left here is a loop over flat instructions.
final class WasmInterpreter extends WasmRuntime {
  /// The interpreter; it holds no state, so one instance serves every
  /// module.
  const WasmInterpreter();

  @override
  String get name => 'interpreter';

  @override
  bool get isMetered => true;

  @override
  WasmInstance instantiate(WasmInstantiation request) =>
      _Instance(request.module, request.imports, request.limits, request.render)
        .._begin();
}

final class _Instance extends WasmInstance {
  _Instance(this._module, this._imports, this._limits, this._render)
    : _globals = <int>[for (final g in _module.globals) g.init] {
    if (_module.kind == WasmModuleKind.render && _render == null) {
      throw const WasmException(
        'a render module is instantiated with WasmInstantiation.render, '
        'which hands it its render imports',
      );
    }
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
  final WasmRenderImports? _render;
  final List<int> _globals;

  /// The fuel the call running now may spend: [WasmLimits.fuelPerStep] for
  /// a step, [WasmLimits.fuelPerFrame] for a frame's render call.
  int _budget = 0;

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
    final refusal = wasmAbiRefusal(
      abi,
      _module.importNames,
      kind: _module.kind,
    );
    if (refusal != null) throw WasmException(refusal);
    _abi = abi;
    _used = 0;
  }

  int _run(int function, List<int> args, {int? fuel}) {
    _budget = fuel ?? _limits.fuelPerStep;
    _fuel = _budget;
    try {
      return _invoke(function, args, 0);
    } finally {
      _used = _budget - (_fuel < 0 ? 0 : _fuel);
    }
  }

  @override
  void step(WasmStep step) {
    if (_module.kind != WasmModuleKind.step) {
      throw const WasmException(
        'a render module is called each frame, not stepped',
      );
    }
    _run(_module.stepFunction, <int>[i32(step.step), i32(step.dtFixed)]);
  }

  @override
  void render(WasmRenderCall call) {
    if (_module.kind != WasmModuleKind.render) {
      throw const WasmException(
        'a step module is stepped, not called each frame: a render module is '
        'declared under "wasmRender"',
      );
    }
    _run(_module.renderFunction, <int>[
      i32(call.frame),
      i32(call.view),
    ], fuel: _limits.fuelPerFrame);
  }

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
      case hostPublish:
        _imports.publish(args[0], args[1], args[2]);
        return 0;
      default:
        return _renderHost(host, args);
    }
  }

  /// A render module's import: its commands and what the frame is, each
  /// `f32` crossing as its bits.
  int _renderHost(int host, List<int> args) {
    final render = _render!;
    switch (host) {
      case hostParam:
        render.param(args[0], args[1], f32Value(args[2]));
        return 0;
      case hostParamFloats:
        // Copied here, during the call, and the copy is what the host
        // reads: the module's memory is never handed out, so nothing the
        // host keeps can see the module write it again.
        final len = u32(args[2]);
        if (len % 4 != 0) {
          throw WasmTrapException(
            'the module handed param_floats $len bytes, which is not a '
            'whole number of 32-bit floats',
          );
        }
        final at = _address(args[1], 0, len);
        final values = Float32List(len ~/ 4);
        for (var i = 0; i < values.length; i++) {
          values[i] = _view.getFloat32(at + i * 4, Endian.little);
        }
        render.paramFloats(args[0], values);
        return 0;
      case hostDraw:
        render.draw();
        return 0;
      case hostTime:
        return f32Bits(render.time);
      case hostViewSize:
        return i32(render.viewSize(args[0]));
      default:
        return i32(render.lightCode(args[0]));
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
          'the module ran out of fuel ($_budget instructions '
          '${_module.kind == WasmModuleKind.render ? 'per frame' : 'per step'})',
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
        case >= 0x5B && <= 0x60:
          final y = f32Value(stack[--sp]);
          final x = f32Value(stack[sp - 1]);
          stack[sp - 1] = _compare(op, x, y) ? 1 : 0;
          pc++;
        case >= 0x8B && <= 0x91:
          stack[sp - 1] = _unaryF32(op, stack[sp - 1]);
          pc++;
        case >= 0x92 && <= 0x98:
          final y = stack[--sp];
          stack[sp - 1] = _binaryF32(op, stack[sp - 1], y);
          pc++;
        case 0xA8 || 0xA9:
          stack[sp - 1] =
              f32Truncate(stack[sp - 1], unsigned: op == 0xA9) ??
              (throw const WasmTrapException(
                'the module truncated a float no 32-bit integer holds',
              ));
          pc++;
        case 0xB2:
          stack[sp - 1] = f32Bits(stack[sp - 1].toDouble());
          pc++;
        case 0xB3:
          stack[sp - 1] = f32Bits(u32(stack[sp - 1]).toDouble());
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

  /// The f32 comparisons, 0x5B–0x60: a NaN equals nothing and is unequal
  /// to everything, as Wasm says and Dart's doubles do.
  static bool _compare(int op, double x, double y) => switch (op) {
    0x5B => x == y,
    0x5C => x != y,
    0x5D => x < y,
    0x5E => x > y,
    0x5F => x <= y,
    _ => x >= y,
  };

  /// The f32 instructions of one operand, 0x8B–0x91, on its bits.
  static int _unaryF32(int op, int bits) => switch (op) {
    0x8B => i32(bits & 0x7FFFFFFF),
    0x8C => i32(bits ^ 0x80000000),
    0x8D => f32Bits(f32Value(bits).ceilToDouble()),
    0x8E => f32Bits(f32Value(bits).floorToDouble()),
    0x8F => f32Bits(f32Value(bits).truncateToDouble()),
    0x90 => f32Bits(f32Nearest(f32Value(bits))),
    _ => f32Bits(math.sqrt(f32Value(bits))),
  };

  /// The f32 instructions of two operands, 0x92–0x98, on their bits.
  static int _binaryF32(int op, int x, int y) => switch (op) {
    0x92 => f32Bits(f32Value(x) + f32Value(y)),
    0x93 => f32Bits(f32Value(x) - f32Value(y)),
    0x94 => f32Bits(f32Value(x) * f32Value(y)),
    0x95 => f32Bits(f32Value(x) / f32Value(y)),
    0x96 => f32MinMax(x, y, max: false),
    0x97 => f32MinMax(x, y, max: true),
    _ => i32((x & 0x7FFFFFFF) | (y & 0x80000000)),
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
    final exported = savedGlobalsOf(_module);
    return <String, Object?>{
      'pages': _pages,
      // Up to the last byte that is not nought: a fresh megabyte of memory
      // is a few characters, not a megabyte of text.
      'memory': base64Encode(Uint8List.sublistView(_memory, 0, last)),
      'globals': <String, Object?>{
        for (final MapEntry(key: name, value: index) in exported.entries)
          name: _globals[index],
      },
      // What the browser cannot reach: the mutable globals the module keeps
      // to itself, `__stack_pointer` among them. Out of the digest.
      'internal': <int>[for (final index in _internalGlobals) _globals[index]],
    };
  }

  /// The mutable globals no export names, by index.
  late final List<int> _internalGlobals = <int>[
    for (var i = 0; i < _globals.length; i++)
      if (_module.globals[i].mutable &&
          !savedGlobalsOf(_module).containsValue(i))
        i,
  ];

  /// Puts back what [save] wrote, or a browser runtime's save, which has no
  /// `internal`: the globals the module keeps to itself are then left as
  /// they are.
  ///
  /// **Everything is checked before anything is replaced**: a state that is
  /// not this module's — pages out of range, memory that is not base64 or
  /// does not fit its pages, a global that is not a number, globals that are
  /// not its exported ones — is refused with a [WasmFormatException] and the
  /// module is left as it was, rather than wiped and then thrown out of with
  /// somebody else's error.
  @override
  void restore(Map<String, Object?> state) {
    const refused = WasmFormatException('not the state of this Wasm module');
    final pages = state['pages'];
    final memory = state['memory'];
    final globals = state['globals'];
    final internal = state['internal'];
    final exported = savedGlobalsOf(_module);
    if (pages is! int ||
        pages < 0 ||
        pages > _maxPages ||
        memory is! String ||
        globals is! Map<String, Object?> ||
        globals.length != exported.length ||
        !exported.keys.every((name) => globals[name] is int) ||
        (internal != null &&
            (internal is! List<Object?> ||
                internal.length != _internalGlobals.length ||
                internal.any((Object? g) => g is! int)))) {
      throw refused;
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(memory);
    } on FormatException catch (_, stackTrace) {
      Error.throwWithStackTrace(refused, stackTrace);
    }
    if (bytes.length > pages * _pageBytes) throw refused;
    _memory = Uint8List(0);
    _setMemory(pages);
    _memory.setRange(0, bytes.length, bytes);
    for (final MapEntry(key: name, value: index) in exported.entries) {
      _globals[index] = globals[name]! as int;
    }
    if (internal is List<Object?>) {
      for (final (i, index) in _internalGlobals.indexed) {
        _globals[index] = internal[i]! as int;
      }
    }
  }
}
