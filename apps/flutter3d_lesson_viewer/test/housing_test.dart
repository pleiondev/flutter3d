/// `ls-i-03`/`ls-e-04`'s own row: a real seven-step control-box service —
/// disassembly down to the bare case, then reassembly back to it — opened
/// the way `main.dart` actually opens it, the same shape
/// `teardown_test.dart` already proves for the engine.
///
///     flutter test test/housing_test.dart
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_lesson_viewer/main.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 9,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Future<LessonReady> _opened() async {
  final cubit = LessonCubit();
  await cubit.open(
    _device(),
    camera: CameraNode(),
    asset: 'assets/levels/housing.json',
  );
  final state = cubit.state;
  expect(state, isA<LessonReady>());
  return state as LessonReady;
}

/// Steps [ready.player] through its first [count] moves, applying each one
/// — the same "a real viewer applies every step it passes through"
/// discipline `teardown_test.dart`'s own last test names.
void _advance(LessonReady ready, int count) {
  for (var i = 0; i < count; i++) {
    ready.player.next();
    ready.player.applyCurrent(ready.camera, nodes: ready.nodes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the seven steps resolve in order, each with its own caption', () async {
    final ready = await _opened();
    expect(ready.player.steps.map((EntityDef e) => e.name), <String>[
      'step-1',
      'step-2',
      'step-3',
      'step-4',
      'step-5',
      'step-6',
      'step-7',
    ]);
    expect(ready.player.current?.string('caption'), 'Блок управления в сборе');
  });

  test('every part the level places starts visible', () async {
    final ready = await _opened();
    expect(
      ready.nodes.keys,
      containsAll(<String>[
        'case-base',
        'housing-lid',
        'circuit-board',
        'battery',
      ]),
    );
    for (final node in ready.nodes.values) {
      expect(node.visible, isTrue, reason: 'nothing has been opened yet');
    }
  });

  test('disassembly: by step 4, only the bare case is left', () async {
    final ready = await _opened();
    _advance(ready, 3);

    expect(ready.player.current?.name, 'step-4');
    expect(ready.nodes['case-base']!.visible, isTrue);
    expect(ready.nodes['housing-lid']!.visible, isFalse);
    expect(ready.nodes['circuit-board']!.visible, isFalse);
    expect(ready.nodes['battery']!.visible, isFalse);
  });

  test(
    'reassembly: each step brings back exactly the part it names, in order',
    () async {
      final ready = await _opened();
      _advance(ready, 3); // down to the bare case

      ready.player.next(); // step-5: the battery goes back in
      ready.player.applyCurrent(ready.camera, nodes: ready.nodes);
      expect(ready.nodes['battery']!.visible, isTrue);
      expect(ready.nodes['circuit-board']!.visible, isFalse);
      expect(ready.nodes['housing-lid']!.visible, isFalse);

      ready.player.next(); // step-6: the board goes back in
      ready.player.applyCurrent(ready.camera, nodes: ready.nodes);
      expect(ready.nodes['circuit-board']!.visible, isTrue);
      expect(ready.nodes['housing-lid']!.visible, isFalse);

      ready.player.next(); // step-7: the lid closes
      ready.player.applyCurrent(ready.camera, nodes: ready.nodes);
      expect(ready.nodes['housing-lid']!.visible, isTrue);
    },
  );

  test(
    'by the last step, the box reads exactly as it did at the first',
    () async {
      final ready = await _opened();
      _advance(ready, 6);

      expect(ready.player.current?.name, 'step-7');
      expect(ready.player.isLast, isTrue);
      for (final node in ready.nodes.values) {
        expect(node.visible, isTrue, reason: 'fully reassembled');
      }
    },
  );
}
