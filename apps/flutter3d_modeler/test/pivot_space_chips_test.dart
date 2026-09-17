/// The pivot and space chips under the transform grid.
///
///     flutter test test/pivot_space_chips_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/display_modes.dart';
import 'package:flutter3d_modeler/src/ui/properties/pivot_space_chips.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('picking Individual calls onPivot with it', (
    WidgetTester tester,
  ) async {
    PivotChip? picked;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PivotAndSpaceChips(
            pivot: PivotChip.median,
            onPivot: (PivotChip to) => picked = to,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Individual'));
    await tester.pump();

    expect(picked, PivotChip.individual);
  });

  testWidgets('the 3D Cursor chip is disabled — there is nowhere for it to '
      'point yet', (WidgetTester tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PivotAndSpaceChips(
            pivot: PivotChip.median,
            onPivot: (_) => calls++,
          ),
        ),
      ),
    );

    // Mutation: leave it enabled, which would let a person pick a pivot
    // `transformPivotOf` silently maps back to median.
    await tester.tap(find.text('3D Cursor'));
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('picking Local calls onSpace with it', (
    WidgetTester tester,
  ) async {
    TransformSpace? picked;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SpaceChips(
            space: TransformSpace.global,
            onSpace: (TransformSpace to) => picked = to,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Local'));
    await tester.pump();

    expect(picked, TransformSpace.local);
  });
}
