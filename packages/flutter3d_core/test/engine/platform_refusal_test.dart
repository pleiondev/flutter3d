// What a platform lacks is refused the way a device's missing feature is:
// an `UnsupportedCapabilityException` naming the capability, which a caller can catch
// as a `CapabilityException`, and not a bare `UnsupportedError`.
import 'package:flutter3d_core/flutter3d_core.dart';
// The browser's half, read on the VM: it imports nothing the VM lacks.
import 'package:flutter3d_core/src/engine/platform/files_web.dart' as web;
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('the browser refuses a file read as a missing file system', () {
    expect(
      () => web.readFileBytes('levels/crypt.json'),
      throwsA(
        isA<UnsupportedCapabilityException>()
            .having((e) => e.feature, 'feature', PlatformFeature.fileSystem)
            .having((e) => e.backend, 'backend', 'the browser')
            .having((e) => e.message, 'message', contains('crypt.json')),
      ),
    );
  });

  test('a platform feature has a stable name', () {
    expect(PlatformFeature.fileSystem.name, 'fileSystem');
    expect(PlatformFeature.fileSystem, isA<Capability>());
  });
}
