/// The player's colour vision: a choice in the settings, and the look a
/// frame is drawn with for it.
///
///     flutter test test/color_vision_setting_test.dart
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _device() => CpuDevice(
  width: 8,
  height: 8,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  test('the setting names a correction, or none', () {
    expect(colorVisionOf(GameConfig()), isNull);
    final deutan = colorVisionOf(
      GameConfig(settings: <String, double>{colorVisionSetting: 2}),
    )!;
    // Mutation: counting the choices from nought puts Off on protan and
    // every kind one along.
    expect(deutan.deficiency, ColorVisionDeficiency.deutan);
    expect(deutan.corrects, isTrue);
    expect(
      colorVisionOf(
        GameConfig(settings: <String, double>{colorVisionSetting: 9}),
      ),
      isNull,
    );
  });

  test('the look carries the table, made once per kind', () {
    final look = ColorVisionLook(_device());
    final config = GameConfig(
      settings: <String, double>{colorVisionSetting: 3},
    );
    final first = look.of(config).lut;
    expect(first, isNotNull);
    // Mutation: uploading a table every frame leaks one a frame.
    expect(look.of(config).lut, same(first));
    config.setSetting(colorVisionSetting, 1);
    expect(look.of(config).lut, isNot(same(first)));
    config.setSetting(colorVisionSetting, 0);
    expect(look.of(config).lut, isNull);
  });

  test('a look with its own table keeps it', () {
    final device = _device();
    final graded = LookSettings(
      lut: const ColorVision.simulate(
        ColorVisionDeficiency.tritan,
      ).upload(device),
    );
    final look = ColorVisionLook(device);
    final config = GameConfig(
      settings: <String, double>{colorVisionSetting: 2},
    );
    expect(look.of(config, graded).lut, same(graded.lut));
  });

  testWidgets('the settings panel offers it, and writes the choice', (
    WidgetTester tester,
  ) async {
    final written = <String, double>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            mixer: Mixer(),
            bindings: DesktopInput.defaultBindings(),
            config: GameConfig(),
            padConnected: false,
            onVolume: (AudioBus bus, double volume) {},
            onSetting: (String name, double value) => written[name] = value,
            onClose: () {},
            actions: const <GameAction>[],
            waitingFor: null,
            onRebind: (GameAction? action) {},
            onResetControls: () {},
            writeFailed: false,
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Deutan'), 100);
    await tester.tap(find.text('Deutan'));
    expect(written[colorVisionSetting], 2.0);
  });
}
