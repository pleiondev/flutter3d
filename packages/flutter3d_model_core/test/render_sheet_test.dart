/// `renderSheet`: the half of `mcp-07n`'s own acceptance that needs no
/// concrete [GraphicsDevice] — `dart test test/render_sheet_test.dart`.
///
/// The pixel-level half (a real cube, a real quadrant, checked against a
/// real [renderProject] call for the same view) lives in
/// `packages/flutter3d_cpu/test/render_sheet_test.dart`, for the same reason
/// `render_project_test.dart` is split the same way — see
/// `render_project.dart`'s own doc comment.
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

void main() {
  test('renderSheetViews names exactly four views', () {
    expect(renderSheetViews, hasLength(4));
    expect(renderSheetViews.toSet(), hasLength(4));
  });
}
