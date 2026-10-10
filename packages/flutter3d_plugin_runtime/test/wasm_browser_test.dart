/// The browser's own WebAssembly, held to what the interpreter is held to
/// where the two can be compared: a state that is not the module's is
/// refused, and the module is left as it was.
///
///     dart test -p chrome test/wasm_browser_test.dart
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

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

void main() {
  test('a damaged state is refused, and the module is left as it was', () {
    // Mutation, one per case: drop the range check on `pages` (a negative
    // grow throws the browser's RangeError), let base64Decode's
    // FormatException out, drop the length check (a RangeError from
    // `setRange`, after the memory was zeroed), cast each global unchecked (a
    // TypeError, after the earlier ones were written), or zero the memory
    // before checking the rest.
    final m = ModuleBuilder()
      ..global(0)
      ..global(0)
      ..memory(1, max: 2)
      ..exportMemory('memory')
      ..exportGlobal('a', 0)
      ..exportGlobal('b', 1);
    m.abi(
      step: <int>[
        ...konst(7), globalSet, 0, ...konst(9), globalSet, 1, //
        ...konst(0), ...konst(42), ...store(),
      ],
    );
    final instance = browserWasmRuntime()!.instantiate(
      WasmModule.decode(m.build()),
      const _Quiet(),
      const WasmLimits(),
    )..step(0, 0);
    final good = instance.save();
    expect(good['globals'], <int>[7, 9]);
    expect(good['memory'], isNot(''));

    Map<String, Object?> damaged(String key, Object? value) =>
        <String, Object?>{...good, key: value};
    final tooLong = base64Encode(Uint8List(65536 + 1)..[65536] = 1);
    final cases = <String, Map<String, Object?>>{
      'negative pages': damaged('pages', -1),
      'pages past the maximum': damaged('pages', 3),
      'pages not a number': damaged('pages', '1'),
      'memory not base64': damaged('memory', 'not*base64!'),
      'memory not text': damaged('memory', 42),
      'memory past its pages': damaged('memory', tooLong),
      'a global not a number': damaged('globals', <Object?>[1, 'two']),
      'a global missing': damaged('globals', <Object?>[1, null]),
      'too few globals': damaged('globals', <Object?>[1]),
      'globals not a list': damaged('globals', 1),
    };
    for (final MapEntry(key: what, value: state) in cases.entries) {
      expect(
        () => instance.restore(state),
        throwsA(
          isA<WasmFormatException>().having(
            (e) => e.message,
            'message',
            'not the state of this Wasm module',
          ),
        ),
        reason: what,
      );
      expect(instance.save(), good, reason: '$what left the module changed');
    }

    // And the state it saved still goes back.
    instance.restore(good);
    expect(instance.save(), good);
  });
}
