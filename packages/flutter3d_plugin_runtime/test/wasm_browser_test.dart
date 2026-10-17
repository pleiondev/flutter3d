/// The browser's own WebAssembly, held to what the interpreter is held to
/// where the two can be compared: a state that is not the module's is
/// refused, and the module is left as it was.
///
///     dart test -p chrome test/wasm_browser_test.dart
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderParameterWrite, RenderProgramFrame;
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
      WasmInstantiation(
        WasmModule.decode(m.build()),
        imports: const _Quiet(),
        limits: const WasmLimits(),
      ),
    )..step(WasmStep(step: 0, dtFixed: 0));
    final good = instance.save();
    expect(good['globals'], <String, Object?>{'a': 7, 'b': 9});
    // What the browser cannot reach is not written: the interpreter's
    // `internal` is its own.
    expect(good.containsKey('internal'), isFalse);
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
      'a global not a number': damaged('globals', <String, Object?>{
        'a': 1,
        'b': 'two',
      }),
      'a global missing': damaged('globals', <String, Object?>{
        'a': 1,
        'b': null,
      }),
      'too few globals': damaged('globals', <String, Object?>{'a': 1}),
      'globals not a map': damaged('globals', <Object?>[7, 9]),
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

  test('a render module says to the frame in the browser what it says on '
      'the interpreter', () {
    // Mutation, one per import: answer view_size with the width for every
    // axis, hand param_floats a view of the browser's memory rather than a
    // copy (the second frame's time overwrites the first's), or leave
    // light_code or draw out of the import object.
    final m = ModuleBuilder()
      ..memory(1, max: 1)
      ..exportMemory('memory');
    final param = m.importOf('param', const <int>[
      i32Type,
      i32Type,
      f32Type,
    ], const <int>[]);
    final floats = m.importOf('param_floats', const <int>[
      i32Type,
      i32Type,
      i32Type,
    ], const <int>[]);
    final time = m.importOf('time', const <int>[], const <int>[f32Type]);
    final size = m.importOf(
      'view_size',
      const <int>[i32Type],
      const <int>[i32Type],
    );
    final light = m.importOf(
      'light_code',
      const <int>[i32Type],
      const <int>[i32Type],
    );
    final draw = m.importOf('draw', const <int>[], const <int>[]);
    List<int> set(int component, List<int> value) => <int>[
      ...konst(0),
      ...konst(component),
      ...value,
      call,
      ...u32(param),
    ];
    m.render(
      node: <int>[
        ...set(0, <int>[...konst(1), call, ...u32(size), f32ConvertI32S]),
        ...set(1, <int>[...konst(0), call, ...u32(light), f32ConvertI32S]),
        ...set(2, <int>[...fconst(0.25), ...fconst(0.5), f32Mul]),
        ...konst(0), call, ...u32(time), ...fstore(), //
        ...konst(4), call, ...u32(time), ...fstore(),
        ...konst(1), ...konst(0), ...konst(8), call, ...u32(floats),
        call, ...u32(draw),
      ],
    );
    final bytes = m.build();
    List<String> said(WasmRuntime runtime) {
      final node = WasmRenderNode(
        const WasmRenderSpec(
          module: 'm.wasm',
          step: 'beat',
          parameters: <String>['tint', 'strength'],
          lights: <String>['tube'],
        ),
        WasmModule.decode(bytes, kind: WasmModuleKind.render),
        plugin: 'acme',
        runtime: runtime,
      );
      final first = _Frame(time: 1.5);
      node.run(first);
      node.run(_Frame(time: 9.0));
      return first.said;
    }

    final interpreted = said(WasmRuntime.interpreter);
    expect(interpreted, <String>[
      'param 0 0 48.000',
      'param 0 1 17.000',
      'param 0 2 0.125',
      'floats 1 1.500 1.500',
      'draw',
    ]);
    expect(said(browserWasmRuntime()!), interpreted);
  });
}

/// A frame that writes down every command it is handed, the floats as they
/// were when it was handed them.
final class _Frame extends RenderProgramFrame {
  _Frame({required this.time});

  final List<String> said = <String>[];

  @override
  final double time;

  @override
  int get frame => 7;

  @override
  int get view => 0;

  @override
  int get width => 64;

  @override
  int get height => 48;

  /// A write of one component reads as `param`, a write of several as
  /// `floats`: the two imports, as the module made them.
  @override
  void setParameter(RenderParameterWrite write) {
    final RenderParameterWrite(:parameter, :component, :values) = write;
    said.add(
      values.length == 1
          ? 'param $parameter $component ${values.single.toStringAsFixed(3)}'
          : 'floats $parameter '
                '${values.map((v) => v.toStringAsFixed(3)).join(' ')}',
    );
  }

  @override
  void draw() => said.add('draw');

  @override
  int? lightCode(String name) => name == 'acme.tube' ? 17 : null;
}
