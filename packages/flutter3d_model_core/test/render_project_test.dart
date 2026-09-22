/// `renderProject`: `mcp-05n`'s own acceptance, the half of it that needs no
/// concrete [GraphicsDevice] — `dart test test/render_project_test.dart`.
///
/// Everything that draws a real picture and checks its pixels lives in
/// `packages/flutter3d_cpu/test/render_project_test.dart` instead: a real
/// [GraphicsDevice] means a real backend, and `flutter3d_model_core` may not
/// depend on one — see `render_project.dart`'s own doc comment for why.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

void main() {
  test('a refusal names the limit, before the device is ever asked for', () {
    var deviceRequested = false;
    expect(
      () => renderProject(
        RenderRequest(project: const ModelProject(), width: 2000, height: 512),
        deviceFactory: (width, height) {
          deviceRequested = true;
          throw StateError('renderProject should have refused before this');
        },
      ),
      throwsA(
        isA<RenderRefusal>().having(
          (e) => e.message,
          'message',
          contains('1024'),
        ),
      ),
    );
    expect(
      deviceRequested,
      isFalse,
      reason: 'a refusal is decided from the request alone',
    );
  });
}
