// A widget drawn into a texture takes the device's own road: wrapped where
// the device takes a `dart:ui` image whole, copied through the host where it
// does not or refuses this one.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// A device that wraps images, or refuses to when [refuses], and records
/// which road each texture took. Anything else it is asked throws.
final class _Wrapping extends GraphicsDevice with PlatformTextures<ui.Image> {
  _Wrapping({this.refuses = false});

  final bool refuses;
  final List<String> roads = <String>[];

  @override
  String get backendName => 'a wrapping fake';

  @override
  TextureHandle textureFromPlatformImage(ui.Image image, {String? label}) {
    if (refuses) {
      throw refuseResource('textureFromPlatformImage', 'not this image');
    }
    roads.add('wrapped');
    return wrapTexture(
      backend: image,
      width: image.width,
      height: image.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      usage: TextureUsage.sampled,
    );
  }

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    roads.add('copied ${pixels.lengthInBytes} bytes');
    return wrapTexture(
      backend: Object(),
      width: width,
      height: height,
      format: format,
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} was not expected');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a device that takes the image whole is handed it, not its pixels',
    () async {
      // Mutation: drop the `is PlatformTextures<ui.Image>` question from
      // `textureFromImage`, and the widget is read back and copied here too.
      final device = _Wrapping();
      final texture = await WidgetTexture(
        device,
      ).draw(const ColoredBox(color: Color(0xFF3366CC)), width: 8, height: 4);
      expect(device.roads, <String>['wrapped']);
      expect(texture?.width, 8);
      expect(texture?.height, 4);
    },
  );

  test(
    'a device that refuses this image is handed its pixels instead',
    () async {
      // Mutation: let the refusal escape, and the sign is never drawn.
      final device = _Wrapping(refuses: true);
      final texture = await WidgetTexture(
        device,
      ).draw(const ColoredBox(color: Color(0xFF3366CC)), width: 8, height: 4);
      expect(device.roads, <String>['copied ${8 * 4 * 4} bytes']);
      expect(texture?.width, 8);
    },
  );
}
