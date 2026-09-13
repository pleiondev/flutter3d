import 'package:flutter/services.dart';
import 'package:flutter3d_editor/src/open_run_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> sendOpenRun(String path) async {
    final call = const StandardMethodCodec().encodeMethodCall(
      MethodCall('openRun', path),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'dev.pleion.flutter3d_editor/openRun',
          call,
          (_) {},
        );
  }

  test('a path macOS sends through the channel reaches the callback', () async {
    String? received;
    final channel = OpenRunChannel(onPath: (path) => received = path);
    addTearDown(channel.dispose);

    await sendOpenRun('/Users/someone/Desktop/bug.f3drun');

    expect(received, '/Users/someone/Desktop/bug.f3drun');
  });

  test('an unrelated method on the same channel is ignored', () async {
    var calls = 0;
    final channel = OpenRunChannel(onPath: (_) => calls++);
    addTearDown(channel.dispose);

    final call = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('somethingElse', 'irrelevant'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'dev.pleion.flutter3d_editor/openRun',
          call,
          (_) {},
        );

    expect(calls, 0);
  });
}
