/// A picture of every mode and sub-mode the editor offers, taken headlessly
/// and held to a reference like every other golden here.
///
///     flutter test test/tutorial_screenshots_test.dart
///     flutter test test/tutorial_screenshots_test.dart --update-goldens
///
/// **Why these exist.** Every page of the modeller tutorial carries an
/// explicit "screenshot pending" placeholder where a picture of the
/// application's own chrome belongs — the panels, the rail, the mode
/// switcher, the dialogs — and says the chrome needs a window nothing in a
/// sandbox can open. It does not: `ModelerScreen` opens the software
/// rasteriser in a headless `flutter test`, and its frames reach the widget
/// tree as an ordinary image (`cpu_frame_presenter.dart`), so a golden of
/// this tree is a photograph of the real editor rather than a mock-up.
///
/// **This file is the reference tour; `tutorial_case_screenshots_test.dart`
/// is the six pages' own named pictures.** A tutorial that promises to cover
/// every mode needs one picture per mode whether or not a case happens to
/// visit it, and those are here — a tour of the application, in the document
/// it opens with.
///
/// Everything shared between the two lives in
/// `tutorial_screenshots_support.dart`.
// A reference picture, held against a committed PNG. Tagged so a run that
// only wants the logic can skip every one of them at once:
//
//     very_good test -x golden
//
// Kept as a tag rather than a flag a test reads, because the decision belongs
// to whoever starts the run and not to the test.
// The second tag is read by `very_good test`, whose optimizer replaces the
// golden comparator with a wrapper `useTolerantGoldens` cannot cast. Written
// without a `<String>` argument because that tool finds it by a regular
// expression reading `@Tags\s*\(\s*\[`.
// ignore: always_specify_types
@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tutorial_screenshots_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useTolerantGoldens('tutorial_screenshots_test.dart');

  bool fonts = false;
  setUpAll(() async {
    fonts = await loadSdkFonts();
  });

  group('every mode the editor offers', () {
    testWidgets('object mode, which is what a launch opens on', (
      WidgetTester tester,
    ) async {
      await launchModeller(tester, fonts: fonts);
      await shootWindow(tester, 'object-mode');
    });

    for (final ModelerMode mode in ModelerMode.values) {
      if (!mode.ready || mode == ModelerMode.object) continue;
      testWidgets('${mode.name} mode', (WidgetTester tester) async {
        await launchModeller(tester, fonts: fonts);
        await switchMode(tester, mode);
        await shootWindow(tester, '${mode.name}-mode');
      });
    }
  });

  group('every sub-mode inside a mode that has them', () {
    for (final MeshSubmode submode in MeshSubmode.values) {
      testWidgets('mesh · ${submode.name}', (WidgetTester tester) async {
        await launchModeller(tester, fonts: fonts);
        await switchMode(tester, ModelerMode.mesh);
        await switchMeshSubmode(tester, submode);
        await shootWindow(tester, 'mesh-${submode.name}');
      });
    }

    for (final AnimationSubmode submode in AnimationSubmode.values) {
      testWidgets('animation · ${submode.name}', (WidgetTester tester) async {
        await launchModeller(tester, fonts: fonts);
        await switchMode(tester, ModelerMode.animation);
        await switchAnimationSubmode(tester, submode);
        await shootWindow(tester, 'animation-${submode.name}');
      });
    }
  });

  group('the screens a person is sent to', () {
    testWidgets('the start screen, which a first launch opens on', (
      WidgetTester tester,
    ) async {
      await launchModeller(tester, fonts: fonts);
      await openByTooltip(
        tester,
        'Start screen — open a file or start a new project',
      );
      await shootWindow(tester, 'start-screen');
    });

    testWidgets('settings', (WidgetTester tester) async {
      await launchModeller(tester, fonts: fonts);
      await openByTooltip(
        tester,
        'Settings — navigation, keys, workspace, language',
      );
      await shootWindow(tester, 'settings-screen');
    });

    testWidgets('the keyboard shortcuts', (WidgetTester tester) async {
      await launchModeller(tester, fonts: fonts);
      await openByTooltip(tester, 'Keyboard shortcuts (?)');
      await shootWindow(tester, 'shortcuts-screen');
    });
  });

  group('the dialogs a person opens over a mode', () {
    // **The tour was every mode and no dialog.** A tutorial that promises
    // every aspect of the editor cannot stop at the chrome behind them: the
    // export sheet, the gallery, the material studio and the primitive menu
    // are each a whole decision a person makes, and each one is reachable
    // from a launch with nothing open but the document the editor starts on.
    //
    // The two that are not here are the two that cannot be: Open and Import
    // hand the platform's own file picker up, and a headless test has no
    // platform to hand it to.
    testWidgets('the export sheet, with its readiness list', (
      WidgetTester tester,
    ) async {
      await launchModeller(tester, fonts: fonts);
      await openExportScreen(tester);
      await shootWindow(tester, 'export-dialog');
    });

    testWidgets('the gallery', (WidgetTester tester) async {
      await launchModeller(tester, fonts: fonts);
      await openByTooltip(
        tester,
        'Gallery \u2014 insert a ready model beside what is open',
      );
      await shootWindow(tester, 'gallery-dialog');
    });

    testWidgets('the material studio', (WidgetTester tester) async {
      await launchModeller(tester, fonts: fonts);
      await openByTooltip(tester, 'Material Studio \u2014 preview a material');
      await shootWindow(tester, 'material-studio-dialog');
    });

    testWidgets('the primitive menu', (WidgetTester tester) async {
      await launchModeller(tester, fonts: fonts);
      await openByTooltip(tester, 'Add a primitive');
      await shootWindow(tester, 'add-primitive-menu');
    });
  });
}
