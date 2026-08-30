/// The minimal example, run the way CI runs everything: with no GPU.
///
/// `openDevice` falls back to the software rasteriser when Impeller will not
/// start, which is exactly what happens under `flutter test` — so this file is
/// both a smoke test and the proof that the fallback story in
/// `minimal_main.dart`'s comment is true.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_example/minimal_main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the minimal example opens a device and draws', (tester) async {
    await tester.pumpWidget(const MinimalApp());

    // The device opens asynchronously; pump until the renderer's first frame
    // replaces the black placeholder.
    await tester.pumpAndSettle();

    // Reaching here means openDevice resolved, the sphere uploaded, and a
    // frame rendered inside build without throwing. The placeholder is the
    // one widget that must be gone.
    expect(find.byKey(const Key('opening')), findsNothing);
  });
}
