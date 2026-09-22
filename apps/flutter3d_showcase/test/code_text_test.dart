/// `codeStyle`'s own font, checked directly rather than through a guide.
///
/// `Menlo`/`Consolas` are real fonts on a desktop and names CanvasKit has
/// nothing to look up on the web, where a guide's code fell back to the
/// app's ordinary proportional font with no error to say so. This is the
/// one place that regresses silently again if the font name ever drifts
/// from the family the asset is bundled under.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/docs/code_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('codeStyle asks for the bundled monospace font, not an OS one', (
    tester,
  ) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            style = codeStyle(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(style.fontFamily, 'RobotoMono');
    // Mutation: leave the OS names in as a fallback. CanvasKit has none of
    // them either, so a fallback list here would only hide the same bug
    // one silent step later.
    expect(style.fontFamilyFallback, anyOf(isNull, isEmpty));
  });
}
