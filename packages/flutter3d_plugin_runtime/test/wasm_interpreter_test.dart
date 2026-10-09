/// The interpreter: 32-bit arithmetic at its edges, control flow, memory,
/// the limits, and a saved state that steps on as the original would.
///
///     dart test test/wasm_interpreter_test.dart
///
/// A step writes its answer into global 0, and the test reads it back
/// through `save()`, the one window the public API has into a module. The
/// arithmetic cases are the ones a 64-bit `int` gets wrong when it is not
/// folded back to 32 bits, or a browser's double when a product passes
/// 2^53. Each test names the mutation that would defeat it.
library;

import 'package:flutter3d_plugin_runtime/src/wasm/wasm.dart';
import 'package:test/test.dart';

import 'wasm/assemble.dart';

final class _Quiet extends WasmImports {
  const _Quiet();

  @override
  int fieldLength(int field) => 0;

  @override
  int fieldGet(int field, int index) => 0;

  @override
  void fieldSet(int field, int index, int value) {}

  @override
  void publish(int event, int a, int b) {}
}

WasmInstance _instance(
  ModuleBuilder m, {
  WasmLimits limits = const WasmLimits(),
}) => WasmRuntime.interpreter.instantiate(
  WasmModule.decode(m.build()),
  const _Quiet(),
  limits,
);

int _global(WasmInstance instance) =>
    (instance.save()['globals']! as List<Object?>).first! as int;

/// Global 0 after one step of [code], which sets it, at [step].
int _after(
  List<int> code, {
  int step = 0,
  int locals = 0,
  void Function(ModuleBuilder m)? also,
}) {
  final m = ModuleBuilder()..global(0);
  also?.call(m);
  m.abi(step: code, locals: locals);
  final instance = _instance(m)..step(step, 0);
  return _global(instance);
}

/// What [code] leaves on the stack, stored into global 0.
int _compute(List<int> code, {void Function(ModuleBuilder m)? also}) =>
    _after(<int>[...code, globalSet, 0], also: also);

Matcher _traps(String saying) => throwsA(
  isA<WasmTrapException>().having(
    (t) => t.message,
    'message',
    contains(saying),
  ),
);

void main() {
  group('arithmetic', () {
    test('a product wraps to its low 32 bits', () {
      // Mutation: `i32(a * b)`. On the VM that is right; compiled to
      // JavaScript the product of these two passes 2^53 and loses its low
      // bits, so the halves in `i32Mul` are what keeps the answer one.
      expect(_compute(<int>[...konst(0x7FFFFFFF), ...konst(2), i32Mul]), -2);
      expect(
        _compute(<int>[
          ...konst(0x12345678),
          ...konst(0x9ABCDEF0.toSigned(32)),
          i32Mul,
        ]),
        (0x12345678 * 0x9ABCDEF0).toSigned(32),
      );
    });

    test('a sum past 2^31 wraps negative', () {
      // Mutation: drop the `i32` around `x + y`.
      expect(
        _compute(<int>[...konst(0x7FFFFFFF), ...konst(1), i32Add]),
        -0x80000000,
      );
    });

    test('dividing by nought traps', () {
      // Mutation: answer nought instead of trapping.
      expect(
        () => _compute(<int>[...konst(1), ...konst(0), i32DivS]),
        _traps('divided by nought'),
      );
    });

    test('-2^31 / -1 traps, and -2^31 % -1 is nought', () {
      // Mutation: drop the overflow check in `_divS`; the quotient 2^31 does
      // not fit and would come back as -2^31 without a word.
      expect(
        () => _compute(<int>[...konst(-0x80000000), ...konst(-1), i32DivS]),
        _traps('overflows'),
      );
      expect(_compute(<int>[...konst(-0x80000000), ...konst(-1), i32RemS]), 0);
    });

    test('a logical shift of a negative number brings in zeros', () {
      // Mutation: implement shr_u as `>>` on the signed value.
      expect(_compute(<int>[...konst(-1), ...konst(28), i32ShrU]), 15);
    });

    test('rotl carries the top bit round', () {
      // Mutation: implement rotl as shl.
      expect(
        _compute(<int>[
          ...konst(0x80000001.toSigned(32)),
          ...konst(1),
          i32Rotl,
        ]),
        3,
      );
    });

    test('counting bits of nought', () {
      // Mutation: start ctz's count at 1, or return 0 for clz(0).
      expect(_compute(<int>[...konst(0), i32Clz]), 32);
      expect(_compute(<int>[...konst(0), i32Ctz]), 32);
      expect(_compute(<int>[...konst(0), i32Popcnt]), 0);
      expect(_compute(<int>[...konst(-1), i32Popcnt]), 32);
    });
  });

  group('control', () {
    test('a loop with br_if sums one to ten', () {
      // Mutation: send a loop's branch to its end rather than its start; the
      // loop then runs once and sums to one.
      expect(
        _after(<int>[
          block, blockVoid, //
          loop, blockVoid,
          localGet, 2, ...konst(10), i32GeS, brIf, 1,
          localGet, 2, ...konst(1), i32Add, localTee, 2,
          localGet, 3, i32Add, localSet, 3,
          br, 0,
          end,
          end,
          localGet, 3, globalSet, 0,
        ], locals: 2),
        55,
      );
    });

    test('br_table goes to the label its index names, or the default', () {
      // Mutation: clamp the index to `count - 1` instead of sending it to
      // the default; step 7 would land on 200.
      final code = <int>[
        block, blockVoid, //
        block, blockVoid,
        block, blockVoid,
        localGet, 0, brTable, 2, 0, 1, 2,
        end,
        ...konst(100), globalSet, 0, br, 1,
        end,
        ...konst(200), globalSet, 0,
        end,
      ];
      expect(_after(code, step: 0), 100);
      expect(_after(code, step: 1), 200);
      expect(_after(code, step: 7), 0);
    });

    test('an if yields the branch its condition picks', () {
      // Mutation: jump to the else on a non-zero condition.
      List<int> pick(int condition) => <int>[
        ...konst(condition),
        ifOp,
        blockI32,
        ...konst(11),
        elseOp,
        ...konst(22),
        end,
      ];
      expect(_compute(pick(1)), 11);
      expect(_compute(pick(0)), 22);
    });
  });

  group('memory', () {
    test(
      'a store is read back, and a data segment is there from the start',
      () {
        // Mutation: copy data segments at offset 0 whatever they say.
        void memory(ModuleBuilder m) => m
          ..memory(1)
          ..data(16, const <int>[7, 0, 0, 0]);
        expect(
          _compute(<int>[
            ...konst(8), ...konst(1234), ...store(), //
            ...konst(8), ...load(),
          ], also: memory),
          1234,
        );
        expect(_compute(<int>[...konst(16), ...load()], also: memory), 7);
      },
    );

    test('a read past the memory traps', () {
      // Mutation: check `at > length` rather than `at + size > length`; the
      // last two bytes of the page would be read as four.
      expect(
        () => _compute(<int>[
          ...konst(65536 - 2),
          ...load(),
        ], also: (m) => m.memory(1)),
        _traps('past its memory'),
      );
    });

    test('memory.grow past the limit answers -1', () {
      // Mutation: trap instead, as a bounds check would; Wasm says -1.
      final m = ModuleBuilder()
        ..global(0)
        ..memory(1);
      m.abi(
        step: <int>[
          ...konst(1), memoryGrow, 0, drop, //
          ...konst(1), memoryGrow, 0, globalSet, 0,
        ],
      );
      final instance = _instance(m, limits: const WasmLimits(memoryPages: 2))
        ..step(0, 0);
      expect(_global(instance), -1);
    });
  });

  group('limits', () {
    test('a loop that never ends runs out of fuel', () {
      // Mutation: skip the fuel count for branches; `loop br 0` is nothing
      // but a branch and would never stop.
      final m = ModuleBuilder()..abi(step: <int>[loop, blockVoid, br, 0, end]);
      expect(
        () =>
            _instance(m, limits: const WasmLimits(fuelPerStep: 1000))
              ..step(0, 0),
        _traps('ran out of fuel'),
      );
    });

    test(
      'fuel is a count: the same step spends the same, to the instruction',
      () {
        // Mutation: spend fuel by time, or reset it inside a call. The budget
        // that exactly covers the step would then pass or trap by chance.
        ModuleBuilder counting() => ModuleBuilder()
          ..abi(
            step: <int>[
              block, blockVoid, //
              loop, blockVoid,
              localGet, 2, ...konst(50), i32GeS, brIf, 1,
              localGet, 2, ...konst(1), i32Add, localSet, 2,
              br, 0,
              end,
              end,
            ],
            locals: 1,
          );
        final first = _instance(counting())..step(0, 0);
        final second = _instance(counting())..step(0, 0);
        expect(first.fuelUsed, greaterThan(50));
        expect(second.fuelUsed, first.fuelUsed);
        expect(
          () => _instance(
            counting(),
            limits: WasmLimits(fuelPerStep: first.fuelUsed),
          )..step(0, 0),
          returnsNormally,
        );
        expect(
          () => _instance(
            counting(),
            limits: WasmLimits(fuelPerStep: first.fuelUsed - 1),
          )..step(0, 0),
          _traps('ran out of fuel'),
        );
      },
    );

    test('calls nested past the limit trap', () {
      // Mutation: count depth from the caller's depth without adding one.
      final m = ModuleBuilder();
      // The first function, so index 0, calling itself.
      final recurse = m.function(0, 0, <int>[call, 0]);
      m.abi(step: <int>[call, recurse]);
      expect(
        () => _instance(m, limits: const WasmLimits(callDepth: 8))..step(0, 0),
        _traps('deeper than 8'),
      );
    });
  });

  test('a restored state steps on exactly as the original did', () {
    // Mutation: leave the globals out of `save`. The counter would come back
    // where the second step left it and the third step would write 4.
    final m = ModuleBuilder()
      ..global(0)
      ..memory(1);
    m.abi(
      step: <int>[
        globalGet, 0, ...konst(1), i32Add, globalSet, 0, //
        ...konst(0), globalGet, 0, ...store(),
      ],
    );
    final instance = _instance(m)..step(0, 0);
    final afterOne = instance.save();
    instance
      ..step(1, 0)
      ..step(2, 0);
    final afterTwo =
        (_instance(m)
              ..step(0, 0)
              ..step(1, 0))
            .save();
    instance
      ..restore(afterOne)
      ..step(1, 0);
    expect(instance.save(), afterTwo);
    expect(_global(instance), 2);
  });
}
