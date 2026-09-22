/// `ux-42`: Quick Setup once, Home at every launch after that.
///
///     flutter test test/launch_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/input_policy.dart';
import 'package:flutter3d_modeler/src/orbit_gestures.dart' show PointerKind;
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/ui/keymap.dart';
import 'package:flutter3d_modeler/src/ui/quick_setup_screen.dart';
import 'package:flutter3d_modeler/src/ui/shortcut_help.dart';
import 'package:flutter3d_modeler/src/ui/shortcut_help_screen.dart';
import 'package:flutter3d_modeler/src/ui/start_screen.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one thing that decides which screen a launch shows.
bool _quickSetupFirst(ModelerSettings settings) => !settings.quickSetupDone;

void main() {
  group('ux-42: which screen a launch shows', () {
    test('an empty store gets Quick Setup, a filled one does not', () {
      // Mutation: show Home first and put the five questions behind
      // Settings. Every one of them is something somebody knows the answer
      // to before they have used the editor, and asking later means asking
      // after the defaults have already annoyed them.
      expect(_quickSetupFirst(const ModelerSettings()), isTrue);
      expect(
        _quickSetupFirst(const ModelerSettings(quickSetupDone: true)),
        isFalse,
      );
    });

    test('and Home is a choice, where Quick Setup is not', () {
      // The default is on, and a person who turns it off lands in the
      // document.
      expect(const ModelerSettings().showHomeAtLaunch, isTrue);
      expect(
        const ModelerSettings(showHomeAtLaunch: false).showHomeAtLaunch,
        isFalse,
      );
    });
  });

  group('ux-42: Quick Setup', () {
    testWidgets('answers with what was chosen, marked done', (
      WidgetTester tester,
    ) async {
      ModelerSettings? answered;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async => answered = await showQuickSetup(
                  context,
                  const ModelerSettings(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Set up the editor'), findsOneWidget);
      // The five, and only the five: no theme row, because this build has one
      // palette and a picker with one option is a control with nothing to
      // decide.
      for (final String asked in <String>[
        'Camera',
        'Keys',
        'Move, rotate and scale',
        'How much of it',
        'Language',
      ]) {
        expect(find.text(asked), findsOneWidget, reason: asked);
      }
      expect(find.text('Theme'), findsNothing);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      // Mutation: answer without `quickSetupDone`. The page would then open
      // again on the next launch, having asked the same five questions and
      // remembered nothing.
      expect(answered!.quickSetupDone, isTrue);
      expect(answered!.workspace, Workspace.essential);
    });
  });

  group('ux-42: Home', () {
    Future<void> pump(
      WidgetTester tester, {
      List<String> recent = const <String>[],
      bool offerLaunchChoice = true,
    }) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: StartScreen(
              recentPaths: recent,
              offerLaunchChoice: offerLaunchChoice,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('draws the four scenario cards', (WidgetTester tester) async {
      await pump(tester);
      // Mutation: offer "New project" and nothing else. The tutorial has four
      // cases and each begins somewhere different; a person following one has
      // to get there before the first paragraph is true.
      for (final StartScenario scenario in StartScenario.values) {
        expect(find.text(scenario.label), findsOneWidget);
      }
      expect(StartScenario.values, hasLength(4));
    });

    testWidgets('the launch checkbox shows only at launch', (
      WidgetTester tester,
    ) async {
      await pump(tester, offerLaunchChoice: false);
      expect(find.byType(Checkbox), findsNothing);

      await pump(tester);
      expect(find.text("Don't show this at launch"), findsOneWidget);
    });
  });

  group('ux-42: Help', () {
    test('has a section for a finger and a pen', () async {
      final List<ShortcutEntry> rows =
          shortcutTable(
                keymapFor(KeymapPreset.standard, apple: false),
                l: await AppLocalizations.delegate.load(const Locale('en')),
              )
              .where((ShortcutEntry it) => it.section == ShortcutSection.touch)
              .toList();

      // Mutation: leave it out. A person on a tablet has no keyboard to read
      // the rest of the screen against, and what `InputPolicy` decides for a
      // finger and a stylus was written down nowhere they could read.
      expect(rows, hasLength(4));
      expect(
        rows.map((ShortcutEntry it) => it.label),
        containsAll(<String>['A finger', 'A pen']),
      );
      // And what it says matches what the policy actually answers.
      expect(
        const InputPolicy().classify(
          kind: PointerKind.touch,
          tool: ToolCategory.sculpting,
        ),
        isA<CameraInput>(),
      );
      expect(
        const InputPolicy().classify(
          kind: PointerKind.stylus,
          tool: ToolCategory.sculpting,
          inverted: true,
        ),
        isA<ToolStroke>().having((ToolStroke it) => it.erase, 'erase', isTrue),
      );
    });

    test('the tutorial link points at the modeller, not the front door', () {
      // Mutation: leave it at the site root. Somebody pressing "Tutorial" in
      // a modeller and landing on a page about a rendering engine has been
      // answered with a different question.
      expect(tutorialUrl.path, '/learn/modeler/');
    });
  });
}
