/// A texture or an environment that cannot be loaded says why, rather than
/// answering null: the first load has nothing good to fall back on.
///
///     flutter test test/hot_swap_load_failure_test.dart
library;

import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _device() => CpuDevice(
  width: 8,
  height: 8,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// The asset bundle as holding [assets] alone, for the rest of the test.
void _bundle(Map<String, List<int>> assets) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        final key = Uri.decodeFull(
          const StringCodec().decodeMessage(message) ?? '',
        );
        final bytes = assets[key];
        return bytes == null
            ? null
            : ByteData.sublistView(Uint8List.fromList(bytes));
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mutation for each: put `if (bytes == null) return null;` back in place of
  // the throw, and the call answers null again.
  test('a texture the bundle does not hold is an AssetNotFoundException '
      'naming it', () async {
    _bundle(const <String, List<int>>{});
    await expectLater(
      HotSwap(enabled: true).loadTexture('decals/sign.png', device: _device()),
      throwsA(
        isA<AssetNotFoundException>().having(
          (AssetNotFoundException e) => e.key,
          'key',
          'decals/sign.png',
        ),
      ),
    );
  });

  test(
    'a texture whose bytes are no image is an ImageFormatException',
    () async {
      _bundle(const <String, List<int>>{
        'decals/sign.png': <int>[1, 2, 3, 4],
      });
      await expectLater(
        HotSwap(
          enabled: true,
        ).loadTexture('decals/sign.png', device: _device()),
        throwsA(isA<Flutter3dException>()),
      );
    },
  );

  test('an environment the bundle does not hold is an '
      'AssetNotFoundException', () async {
    _bundle(const <String, List<int>>{});
    await expectLater(
      HotSwap(enabled: true).loadEnvironment('sky/noon.hdr', device: _device()),
      throwsA(isA<AssetNotFoundException>()),
    );
  });

  test('an environment whose bytes do not decode says so', () async {
    _bundle(const <String, List<int>>{
      'sky/noon.hdr': <int>[1, 2, 3, 4],
    });
    await expectLater(
      HotSwap(enabled: true).loadEnvironment('sky/noon.hdr', device: _device()),
      throwsA(isA<Flutter3dException>()),
    );
  });
}
