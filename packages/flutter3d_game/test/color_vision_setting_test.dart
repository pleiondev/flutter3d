/// The player's colour vision: a choice in the settings, and the look a
/// frame is drawn with for it.
///
///     flutter test test/color_vision_setting_test.dart
library;

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _device() => CpuDevice(
  width: 8,
  height: 8,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  test('the setting names a correction, or none', () {
    expect(colorVisionOf(const GameSettings()), isNull);
    final deutan = colorVisionOf(
      const GameSettings().withValue(GameSettingKeys.colorVision, 2),
    )!;
    // Mutation: counting the choices from nought puts Off on protan and
    // every kind one along.
    expect(deutan.deficiency, ColorVisionDeficiency.deutan);
    expect(deutan.corrects, isTrue);
    expect(
      colorVisionOf(
        const GameSettings().withValue(GameSettingKeys.colorVision, 9),
      ),
      isNull,
    );
  });

  test('the look carries the table, made once per kind', () {
    final look = ColorVisionLook(_device());
    final config = const GameSettings().withValue(
      GameSettingKeys.colorVision,
      3,
    );
    final first = look.of(config).lut;
    expect(first, isNotNull);
    // Mutation: uploading a table every frame leaks one a frame.
    expect(look.of(config).lut, same(first));
    expect(
      look.of(config.withValue(GameSettingKeys.colorVision, 1)).lut,
      isNot(same(first)),
    );
    expect(
      look.of(config.withValue(GameSettingKeys.colorVision, 0)).lut,
      isNull,
    );
  });

  test('a look with its own table keeps it', () {
    final device = _device();
    final graded = LookSettings(
      lut: const ColorVision.simulate(
        ColorVisionDeficiency.tritan,
      ).upload(device),
    );
    final look = ColorVisionLook(device);
    final config = const GameSettings().withValue(
      GameSettingKeys.colorVision,
      2,
    );
    expect(look.of(config, graded).lut, same(graded.lut));
  });
}
