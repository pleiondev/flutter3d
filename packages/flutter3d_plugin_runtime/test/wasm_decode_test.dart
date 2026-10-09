/// What Wasm plugin ABI 1 refuses, and that it refuses it at load with a
/// sentence naming what it found.
///
///     dart test test/wasm_decode_test.dart
///
/// Every module here is assembled by hand in `wasm/assemble.dart`, so no
/// toolchain is needed to run it. Each test was written by breaking what it
/// covers first; the mutation that would defeat it is named in the test.
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

Matcher _refused(String saying) => throwsA(
  isA<WasmException>().having((r) => r.message, 'message', contains(saying)),
);

void main() {
  test('a module with nothing wrong decodes and instantiates', () {
    // Mutation: require a memory section. A module with no memory is ABI 1.
    final module = WasmModule.decode((ModuleBuilder()..abi()).build());
    expect(
      () => WasmRuntime.interpreter.instantiate(
        module,
        const _Quiet(),
        const WasmLimits(),
      ),
      returnsNormally,
    );
  });

  group('values', () {
    test('an f64 instruction is refused as not 32-bit', () {
      // Mutation: take 0x44 out of the refused ranges. It falls to "does not
      // have", which says nothing about why floats are out.
      final m = ModuleBuilder()
        ..abi(step: <int>[0x44, 0, 0, 0, 0, 0, 0, 0xF0, 0x3F, drop]);
      expect(
        () => WasmModule.decode(m.build()),
        _refused('32-bit integers only'),
      );
    });

    test('an i64 instruction is refused as not 32-bit', () {
      // Mutation: take 0x42 (i64.const) out of the refused ranges; it is
      // then read as an instruction ABI 1 merely does not have.
      final m = ModuleBuilder()..abi(step: <int>[0x42, 1, 0x42, 2, 0x7C, drop]);
      expect(
        () => WasmModule.decode(m.build()),
        _refused('32-bit integers only'),
      );
    });

    test('an i64 parameter is refused where the type is declared', () {
      // Mutation: accept 0x7E in `_valueType`.
      final m = ModuleBuilder()..type(1, 0, valueType: 0x7E);
      m.abi();
      expect(() => WasmModule.decode(m.build()), _refused('uses an i64'));
    });
  });

  group('imports', () {
    test('an import ABI 1 does not offer is refused by name', () {
      // Mutation: accept any name from module f3d. A module could then name
      // a clock and be handed whatever the host had under that name.
      final m = ModuleBuilder()..import('clock', 0, 1);
      m.abi();
      expect(() => WasmModule.decode(m.build()), _refused('"f3d.clock"'));
    });

    test('a module other than f3d is refused', () {
      // Mutation: check the name and not the module.
      final m = ModuleBuilder()..import('field_get', 2, 1, module: 'env');
      m.abi();
      expect(() => WasmModule.decode(m.build()), _refused('"env.field_get"'));
    });

    test('an ABI import with the wrong signature is refused', () {
      // Mutation: skip the signature comparison. field_get would be called
      // with one argument where the host reads two.
      final m = ModuleBuilder()..import('field_get', 1, 1);
      m.abi();
      expect(() => WasmModule.decode(m.build()), _refused('takes 1'));
    });
  });

  group('structure', () {
    test('a table is refused', () {
      // Mutation: skip section 4 like a custom section.
      final m = ModuleBuilder()
        ..section(4, <int>[1, 0x70, 0, 1])
        ..abi();
      expect(() => WasmModule.decode(m.build()), _refused('table'));
    });

    test('a module without f3d_abi is refused', () {
      // Mutation: drop the export check; the module is then run without
      // having said which ABI it was written for.
      final m = ModuleBuilder();
      m.export('f3d_step', m.function(2, 0, const <int>[]));
      expect(() => WasmModule.decode(m.build()), _refused('f3d_abi'));
    });

    test('a branch out of the function is refused', () {
      // Mutation: skip the depth check in `_label`; the branch would read a
      // frame that is not there.
      final m = ModuleBuilder()..abi(step: <int>[br, 5]);
      expect(() => WasmModule.decode(m.build()), _refused('branches out'));
    });

    test('an instruction with nothing to pop is refused', () {
      // Mutation: let `_pop` go below the block's height.
      final m = ModuleBuilder()..abi(step: <int>[i32Add, drop]);
      expect(() => WasmModule.decode(m.build()), _refused('needs a value'));
    });

    test('setting an immutable global is refused', () {
      // Mutation: skip the mutability check.
      final m = ModuleBuilder()..global(1, mutable: false);
      m.abi(step: <int>[...konst(2), globalSet, 0]);
      expect(() => WasmModule.decode(m.build()), _refused('immutable'));
    });
  });

  group('at instantiation', () {
    test('a module written for another ABI is refused with both numbers', () {
      // Mutation: skip the f3d_abi call in `_begin`.
      final module = WasmModule.decode((ModuleBuilder()..abi(abi: 2)).build());
      expect(
        () => WasmRuntime.interpreter.instantiate(
          module,
          const _Quiet(),
          const WasmLimits(),
        ),
        _refused('ABI 2 and this engine provides ABI 1'),
      );
    });

    test('a memory starting above the limit is refused', () {
      // Mutation: clamp the starting pages to the limit instead.
      final module = WasmModule.decode(
        (ModuleBuilder()
              ..memory(4)
              ..abi())
            .build(),
      );
      expect(
        () => WasmRuntime.interpreter.instantiate(
          module,
          const _Quiet(),
          const WasmLimits(memoryPages: 2),
        ),
        _refused('starts at 4 pages'),
      );
    });
  });
}
