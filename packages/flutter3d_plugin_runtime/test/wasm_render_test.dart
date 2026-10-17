/// Wasm plugin ABI 3's render modules: decoded as what the section that
/// declares them says, computing in `f32`, run in an instance of their own,
/// their commands reaching a render step by the index the declaration gives.
///
///     dart test test/wasm_render_test.dart
///
/// Every module is assembled by hand in `wasm/assemble.dart`; the sample in
/// `example/plugin/pulse.wasm`, built by an outside toolchain, is held in
/// the example's own suite. Each test names the mutation that would defeat
/// it.
library;

import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginException, RenderProgramFrame;
import 'package:flutter3d_plugin_runtime/src/wasm/wasm.dart';
import 'package:test/test.dart';

import 'wasm/assemble.dart';

/// A frame that writes down every command it is handed.
final class _Frame extends RenderProgramFrame {
  _Frame({this.time = 0.0});

  final List<String> said = <String>[];
  final List<Float32List> floats = <Float32List>[];

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

  @override
  void setParameter(int parameter, int component, double value) {
    if (component > 3) {
      throw const PluginException('the stage has no fifth component');
    }
    said.add('param $parameter $component $value');
  }

  @override
  void setParameterFloats(int parameter, Float32List values) {
    floats.add(values);
    said.add('floats $parameter ${values.length}');
  }

  @override
  void draw() => said.add('draw');

  @override
  int? lightCode(String name) => name == 'acme.tube' ? 17 : null;
}

Matcher _refused(String saying) => throwsA(
  isA<WasmException>().having((r) => r.message, 'message', contains(saying)),
);

Matcher _trapped(String saying) => throwsA(
  isA<WasmTrapException>().having(
    (r) => r.message,
    'message',
    contains(saying),
  ),
);

WasmModule _render(ModuleBuilder m) =>
    WasmModule.decode(m.build(), kind: WasmModuleKind.render);

WasmRenderNode _node(
  ModuleBuilder m, {
  List<String> parameters = const <String>['tint', 'strength'],
  List<String> lights = const <String>[],
  WasmLimits limits = const WasmLimits(),
}) => WasmRenderNode(
  WasmRenderSpec(
    module: 'm.wasm',
    step: 'beat',
    parameters: parameters,
    lights: lights,
    limits: limits,
  ),
  _render(m),
  plugin: 'acme',
);

/// A module whose node sets parameter 1, component 0, to [value] — an f32
/// expression — and draws.
ModuleBuilder _setting(List<int> value, {List<int> locals = const <int>[]}) {
  final m = ModuleBuilder();
  final param = m.importOf('param', const <int>[
    i32Type,
    i32Type,
    f32Type,
  ], const <int>[]);
  final draw = m.importOf('draw', const <int>[], const <int>[]);
  m.render(
    node: <int>[
      ...konst(1),
      ...konst(0),
      ...value,
      call,
      ...u32(param),
      call,
      ...u32(draw),
    ],
    locals: locals,
  );
  return m;
}

/// The value [_setting]'s module sets, run once.
double _computed(List<int> value, {double time = 0.0}) {
  final frame = _Frame(time: time);
  _node(_setting(value)).run(frame);
  return double.parse(frame.said.first.split(' ').last);
}

void main() {
  group('a render module is told apart by its section', () {
    test('it decodes as one, and the same bytes are refused as a step '
        'module', () {
      // Mutation: allow f32 in every module. A step module's numbers would
      // then differ between the VM and a browser, and a replay would part.
      final bytes = _setting(fconst(0.5)).build();
      expect(
        WasmModule.decode(bytes, kind: WasmModuleKind.render).kind,
        WasmModuleKind.render,
      );
      expect(() => WasmModule.decode(bytes), _refused('uses an f32'));
    });

    test('it exports f3d_render_node and needs no f3d_step', () {
      // Mutation: require f3d_step of every module. A render module would
      // have to carry a step the host never calls.
      final m = ModuleBuilder()..abi(abi: 3);
      expect(
        () => WasmModule.decode(m.build(), kind: WasmModuleKind.render),
        _refused('exports no f3d_render_node'),
      );
      expect(() => _render(ModuleBuilder()..render()), returnsNormally);
    });

    test('each kind is refused the other\'s imports, by name', () {
      // Mutation: offer one table of imports to both. A render module could
      // write a world field from a frame a server never draws.
      final reaching = ModuleBuilder()..import('field_get', 2, 1);
      reaching.render();
      expect(() => _render(reaching), _refused('is a step module\'s'));
      final drawing = ModuleBuilder()..importOf('draw', const [], const []);
      drawing.abi(abi: 3);
      expect(
        () => WasmModule.decode(drawing.build()),
        _refused('is a render module\'s'),
      );
    });

    test('a render module written before ABI 3 is refused with both '
        'numbers', () {
      // Mutation: drop the kind from `wasmAbiRefusal`. A module that says
      // ABI 2 would be run with commands its ABI does not have.
      expect(wasmRenderAbi, 3);
      expect(wasmPluginAbiMax, greaterThanOrEqualTo(wasmRenderAbi));
      expect(
        () => _node(ModuleBuilder()..render(abi: 2)),
        _refused('render modules arrived in ABI 3'),
      );
    });

    test('a step module that exports f3d_render_node is not read for it', () {
      // Mutation: call a step module's f3d_render_node. Its section says it
      // steps the simulation; a name it exports does not make it draw.
      final m = ModuleBuilder()..abi(abi: 2);
      m.export(wasmRenderNodeExport, m.function(2, 0, const <int>[]));
      final module = WasmModule.decode(m.build());
      expect(module.kind, WasmModuleKind.step);
      expect(
        () => WasmRenderNode(
          const WasmRenderSpec(module: 'm.wasm', step: 'beat'),
          module,
          plugin: 'acme',
        ),
        _refused('decoded as a step module'),
      );
    });
  });

  group('values', () {
    test('f32 arithmetic is a float\'s, correctly rounded', () {
      // Mutation: compute in doubles and hand the double back. 0.1 + 0.2
      // would cross as a number no float holds.
      expect(
        _computed(<int>[...fconst(0.1), ...fconst(0.2), f32Add]),
        (Float32List(1)..[0] = 0.1 + 0.2)[0],
      );
      expect(_computed(<int>[...fconst(7), ...fconst(2), f32Div]), 3.5);
      expect(_computed(<int>[...fconst(-2.5), f32Abs]), 2.5);
      expect(_computed(<int>[...fconst(2.5), f32Neg]), -2.5);
      expect(_computed(<int>[...fconst(1.75), f32Floor]), 1.0);
      expect(_computed(<int>[...fconst(16), f32Sqrt]), 4.0);
      expect(_computed(<int>[...fconst(3), ...fconst(5), f32Mul]), 15.0);
      expect(_computed(<int>[...fconst(3), ...fconst(5), f32Sub]), -2.0);
    });

    test('nearest rounds a half to even, and min keeps nought\'s sign', () {
      // Mutation: round half away from nought, as Dart's round does.
      expect(_computed(<int>[...fconst(2.5), f32Nearest]), 2.0);
      expect(_computed(<int>[...fconst(3.5), f32Nearest]), 4.0);
      expect(_computed(<int>[...fconst(-0.25), f32Nearest]).isNegative, isTrue);
      expect(
        _computed(<int>[...fconst(-0.0), ...fconst(0.0), f32Min]).isNegative,
        isTrue,
      );
      expect(_computed(<int>[...fconst(1), ...fconst(-1), f32Max]), 1.0);
    });

    test('an i32 and an f32 cross only by a conversion', () {
      // Mutation: count values without their types. An f32 handed to
      // i32.add would add its bits.
      expect(_computed(<int>[...konst(-3), f32ConvertI32S]), -3.0);
      final mixed = ModuleBuilder()
        ..render(node: <int>[...fconst(1), ...konst(1), i32Add, drop]);
      expect(() => _render(mixed), _refused('is handed an f32'));
    });

    test('a truncation no i32 holds traps', () {
      // Mutation: saturate instead. A NaN would cross as nought, quietly.
      final m = ModuleBuilder()
        ..render(
          node: <int>[...fconst(0), ...fconst(0), f32Div, i32TruncF32S, drop],
        );
      expect(() => _node(m).run(_Frame()), _trapped('no 32-bit integer'));
    });

    test('f64 and i64 stay refused in a render module', () {
      // Mutation: open the whole float range with f32.
      final m = ModuleBuilder()..render(node: <int>[0x42, 1, drop]);
      expect(() => _render(m), _refused('i32 and f32 only'));
    });
  });

  group('commands', () {
    test('param and draw reach the frame by the declaration\'s index', () {
      // Mutation: hand the frame the raw index without checking it against
      // the declaration. A module could set a parameter that is not there.
      final frame = _Frame(time: 1.25);
      _node(_setting(<int>[...fconst(0.75)])).run(frame);
      expect(frame.said, <String>['param 1 0 0.75', 'draw']);

      final m = ModuleBuilder();
      final param = m.importOf('param', const <int>[
        i32Type,
        i32Type,
        f32Type,
      ], const <int>[]);
      m.render(
        node: <int>[
          ...konst(2),
          ...konst(0),
          ...fconst(1),
          call,
          ...u32(param),
        ],
      );
      expect(() => _node(m).run(_Frame()), _trapped('declares 2'));
    });

    test('a refusal of the frame\'s is a trap of the module\'s', () {
      // Mutation: let a PluginException out of the import. The renderer
      // would see the plugin's mistake as the engine's.
      final m = ModuleBuilder();
      final param = m.importOf('param', const <int>[
        i32Type,
        i32Type,
        f32Type,
      ], const <int>[]);
      m.render(
        node: <int>[
          ...konst(0),
          ...konst(9),
          ...fconst(1),
          call,
          ...u32(param),
        ],
      );
      expect(() => _node(m).run(_Frame()), _trapped('fifth component'));
    });

    test('param_floats copies the floats during the call', () {
      // Mutation: hand the frame a view of the module's memory. What the
      // host kept would change under it the next time the module wrote.
      final m = ModuleBuilder()..memory(1);
      final floats = m.importOf('param_floats', const <int>[
        i32Type,
        i32Type,
        i32Type,
      ], const <int>[]);
      final time = m.importOf('time', const <int>[], const <int>[f32Type]);
      m.render(
        node: <int>[
          // Writes the frame's time at 0 and 4, then hands both over.
          ...konst(0), call, ...u32(time), ...fstore(),
          ...konst(4), call, ...u32(time), ...fstore(),
          ...konst(0), ...konst(0), ...konst(8), call, ...u32(floats),
        ],
      );
      final node = _node(m);
      final first = _Frame(time: 1.5);
      node.run(first);
      node.run(_Frame(time: 9.0));
      expect(first.floats.single, <double>[1.5, 1.5]);

      final ragged = ModuleBuilder()..memory(1);
      final again = ragged.importOf('param_floats', const <int>[
        i32Type,
        i32Type,
        i32Type,
      ], const <int>[]);
      ragged.render(
        node: <int>[...konst(0), ...konst(0), ...konst(6), call, ...u32(again)],
      );
      expect(
        () => _node(ragged).run(_Frame()),
        _trapped('not a whole number of 32-bit floats'),
      );
    });

    test('the frame\'s size, time and light codes cross as the ABI says', () {
      // Mutation: answer view_size with the width for every axis.
      final m = ModuleBuilder();
      final param = m.importOf('param', const <int>[
        i32Type,
        i32Type,
        f32Type,
      ], const <int>[]);
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
          ...set(2, <int>[...konst(1), call, ...u32(light), f32ConvertI32S]),
        ],
      );
      final frame = _Frame();
      _node(m, lights: const <String>['acme.tube', 'other']).run(frame);
      expect(frame.said, <String>[
        'param 0 0 48.0',
        'param 0 1 17.0',
        'param 0 2 -1.0',
      ]);
    });
  });

  group('the instance of its own', () {
    test('a frame\'s budget is counted per frame, and a trap latches', () {
      // Mutation: count a render call against fuelPerStep. A render node
      // could take a frame's worth of a slow phone's time per step.
      final m = ModuleBuilder()
        ..render(node: <int>[loop, blockVoid, br, 0, end]);
      final node = _node(m, limits: const WasmLimits(fuelPerFrame: 50));
      expect(() => node.run(_Frame()), _trapped('50 instructions per frame'));
      expect(node.trapped, contains('per frame'));
      expect(() => node.run(_Frame()), _trapped('per frame'));
    });

    test('a frame limit reads and writes back only where it was given', () {
      // Mutation: write fuelPerFrame always. Every step system's declaration
      // a 1.0 tool saved would gain a key it never had.
      expect(const WasmLimits().toJson().containsKey('fuelPerFrame'), isFalse);
      final read = WasmLimits.fromJson(const <String, Object?>{
        'fuelPerFrame': 77,
      });
      expect(read.fuelPerFrame, 77);
      expect(read.toJson()['fuelPerFrame'], 77);
    });

    test('a step module is not called each frame, nor a render module '
        'stepped', () {
      // Mutation: let the interpreter run whichever export is there.
      final step = WasmRuntime.interpreter.instantiate(
        WasmInstantiation(
          WasmModule.decode((ModuleBuilder()..abi()).build()),
          imports: const _Quiet(),
          limits: const WasmLimits(),
        ),
      );
      expect(() => step.render(WasmRenderCall()), _refused('stepped'));
      expect(
        () => WasmRuntime.interpreter.instantiate(
          WasmInstantiation(
            _render(ModuleBuilder()..render()),
            imports: const _Quiet(),
            limits: const WasmLimits(),
          ),
        ),
        _refused('WasmInstantiation.render'),
      );
    });
  });

  group('the declaration', () {
    test('reads and writes back, its unknown keys kept', () {
      // Mutation: drop `lights` from toJson. A tool saving the document
      // would leave the module asking for a light it no longer declares.
      final spec = WasmRenderSpec.fromJson(const <String, Object?>{
        'module': 'pulse.wasm',
        'step': 'beat',
        'parameters': <Object?>['tint'],
        'lights': <Object?>['tube'],
        'later': 1,
      });
      expect(spec.toJson(), <String, Object?>{
        'module': 'pulse.wasm',
        'step': 'beat',
        'parameters': <String>['tint'],
        'lights': <String>['tube'],
        'limits': const WasmLimits().toJson(),
        'later': 1,
      });
      expect(
        () => WasmRenderSpec.fromJson(const <String, Object?>{
          'module': 'pulse.wasm',
        }),
        throwsA(isA<WasmFormatException>()),
      );
    });

    test('a bare light is the plugin\'s own, a dotted one as written', () {
      // Mutation: hand the frame the bare name. A module of plugin acme
      // would ask for `tube`, which no hook packs.
      final m = ModuleBuilder();
      final param = m.importOf('param', const <int>[
        i32Type,
        i32Type,
        f32Type,
      ], const <int>[]);
      final light = m.importOf(
        'light_code',
        const <int>[i32Type],
        const <int>[i32Type],
      );
      m.render(
        node: <int>[
          ...konst(0),
          ...konst(0),
          ...konst(0),
          call,
          ...u32(light),
          f32ConvertI32S,
          call,
          ...u32(param),
        ],
      );
      final frame = _Frame();
      _node(m, lights: const <String>['tube']).run(frame);
      expect(frame.said, <String>['param 0 0 17.0']);
    });
  });
}

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
