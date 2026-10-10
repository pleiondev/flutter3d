/// `renderProject`: `mcp-05n`'s own acceptance, the half of it that needs no
/// concrete [GraphicsDevice] — `dart test test/render_project_test.dart`.
///
/// Everything that draws a real picture and checks its pixels lives in
/// `packages/flutter3d_cpu/test/render_project_test.dart` instead: a real
/// [GraphicsDevice] means a real backend, and `flutter3d_model_core` may not
/// depend on one — see `render_project.dart`'s own doc comment for why.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_core/src/selection_tint.dart';
import 'package:test/test.dart';

void main() {
  test('a selection is the sRGB mix of the paint and the orange', () {
    // Mutation: mix `base.r` (linear) rather than the encoded channel, as
    // the code did after the `LinearColor` move. The paint's share all but
    // vanishes: red comes back 0.613 where it should be 0.68.
    final tint = selectionTint(LinearColor.fromSrgb(0.2, 0.4, 0.6, 0.5));
    final srgb = tint.toSrgb();
    expect(srgb.r, closeTo(0.2 * 0.4 + 0.6, 1e-12));
    expect(srgb.g, closeTo(0.4 * 0.4 + 0.55 * 0.6, 1e-12));
    expect(srgb.b, closeTo(0.6 * 0.4, 1e-12));
    expect(tint.a, 0.5);
  });

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
