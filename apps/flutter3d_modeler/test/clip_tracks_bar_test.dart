/// `anim-18`'s own bottom slot: the blend slider that drives
/// `TimelinePreviewWiring.crossFadeTo`.
///
///     flutter test test/clip_tracks_bar_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/clip_tracks_bar.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? clipName,
  double blendSeconds = 0.15,
  ValueChanged<double>? onBlendChanged,
  VoidCallback? onPreview,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: SizedBox(
        height: ModelerMetrics.retargetTracksBar,
        child: ClipTracksBar(
          clipName: clipName,
          blendSeconds: blendSeconds,
          onBlendChanged: onBlendChanged ?? (_) {},
          onPreview: onPreview,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('with nothing retargeted yet, the row reads so and disables '
      'the slider and preview', (tester) async {
    await _pump(tester);

    expect(find.text('No retargeted clip yet'), findsOneWidget);
    final Slider slider = tester.widget(find.byType(Slider));
    expect(slider.onChanged, isNull);
    final TextButton preview = tester.widget(
      find.widgetWithText(TextButton, 'Preview'),
    );
    expect(preview.onPressed, isNull);
  });

  testWidgets('with a clip name, the row shows it and enables both', (
    tester,
  ) async {
    var previewed = 0;
    await _pump(tester, clipName: 'mocap walk', onPreview: () => previewed++);

    expect(find.text('mocap walk'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Preview'));
    expect(previewed, 1);
  });

  testWidgets('dragging the slider reports the new duration', (tester) async {
    final reported = <double>[];
    await _pump(tester, clipName: 'mocap walk', onBlendChanged: reported.add);

    await tester.drag(find.byType(Slider), const Offset(40, 0));

    expect(reported, isNotEmpty);
    expect(reported.last, greaterThan(0.15));
  });
}
