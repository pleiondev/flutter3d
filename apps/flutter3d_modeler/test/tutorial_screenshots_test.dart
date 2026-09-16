/// The tutorial's own screenshots of the running application, taken
/// headlessly and held to a reference like every other golden here.
///
///     flutter test test/tutorial_screenshots_test.dart
///     flutter test test/tutorial_screenshots_test.dart --update-goldens
///
/// **Why these exist.** Every page of the modeller tutorial carries an
/// explicit "screenshot pending" placeholder where a picture of the
/// application's own chrome belongs — the panels, the rail, the mode
/// switcher, the dialogs. Only the pure-3D "expected result" pictures are
/// real, because those come from a headless `render` call that needs no
/// window. A screenshot taken by hand on somebody's machine is a screenshot
/// that is wrong the first time a panel moves and that nobody notices is
/// wrong, which is the failure mode `doc/modeler-tutorial-gaps.md`'s own
/// last section already records for the pictures that *are* checked.
///
/// **The whole application, viewport included.** `ModelerScreen` opens a
/// real device: in a headless `flutter test` that is the software
/// rasteriser, whose frames reach the widget tree as an ordinary `RawImage`
/// (`cpu_frame_presenter.dart`). So a golden of this tree is a picture of
/// the real editor — the real 3D in the middle and the real panels around
/// it — rather than a mock-up of one.
///
/// **One file per screen, named for what the tutorial calls it**, under
/// `test/goldens/screens/`. Regenerating them is one command, which is the
/// whole point: a panel that moves moves in every tutorial page at once.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/main.dart' hide main;
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every read with nothing and every write as if it landed, so a
/// screenshot run touches no real autosave slot.
final class _NullBinaryStorage implements BinaryStorage {
  @override
  Future<Uint8List?> read(String name) async => null;

  @override
  Future<bool> write(String name, Uint8List contents) async => true;

  @override
  Future<void> remove(String name) async {}
}

/// A settings document in memory, so a screenshot run neither reads a
/// person's own preferences nor writes over them.
final class _MemorySettings implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

/// The window every screenshot is taken in.
///
/// 1440×900 is what the design was drawn against and what `shell_test`
/// measures the frame at, so a picture here lines up with the numbers that
/// document says.
const Size _window = Size(1440, 900);

/// Where the SDK keeps the fonts a real build draws with.
///
/// **A screenshot with no fonts is a screenshot of boxes.** `flutter test`
/// loads no font at all by default — every glyph, text and icon alike, is a
/// filled rectangle, which is right for a layout golden and useless for a
/// picture somebody is meant to read. The SDK ships Roboto and the Material
/// icon font in its own cache, and the Dart running this test *is* that
/// cache's own: `bin/cache/dart-sdk/bin/dart`, three directories under the
/// one holding `artifacts/`. Derived rather than written down, so this works
/// on whichever machine or CI runner the SDK is installed on.
Directory? _sdkFonts() {
  Directory at = File(Platform.resolvedExecutable).parent;
  for (var up = 0; up < 8; up++) {
    final Directory fonts = Directory('${at.path}/artifacts/material_fonts');
    if (fonts.existsSync()) return fonts;
    final Directory parent = at.parent;
    if (parent.path == at.path) break;
    at = parent;
  }
  return null;
}

/// Loads Roboto and the Material icons, or answers false where the SDK's own
/// cache is not where it usually is.
///
/// False rather than a throw: a golden of boxes is still a golden of the
/// right *layout*, and a run that cannot find the fonts should say so and
/// skip rather than fail a suite over where somebody's SDK lives.
Future<bool> _loadFonts() async {
  final Directory? fonts = _sdkFonts();
  if (fonts == null) return false;
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final String file in files) {
      final File it = File('${fonts.path}/$file');
      if (!it.existsSync()) continue;
      loader.addFont(
        it.readAsBytes().then((Uint8List bytes) => bytes.buffer.asByteData()),
      );
    }
    await loader.load();
  }

  await load('Roboto', <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', <String>['MaterialIcons-Regular.otf']);
  return true;
}

/// A golden comparator that allows a small share of the picture to differ.
///
/// **A screenshot of a live application is not byte-stable, and pretending
/// otherwise would mean deleting the parts that are true.** The status line
/// carries the last frame's own cost in milliseconds, which is a real
/// measurement of a real render and is different every run; the software
/// rasteriser's own anti-aliasing moves a pixel at a silhouette edge. Both
/// are a handful of pixels out of 1.3 million, and a comparison that failed
/// on them would be one nobody could keep green — so it is given a budget,
/// the same way `cross_backend_test.dart` gives one to two backends drawing
/// the same scene.
///
/// The budget is deliberately small: a panel that moved, a label that
/// changed, a mode that stopped drawing its own rail are all far past it.
class _TolerantGoldens extends LocalFileComparator {
  _TolerantGoldens(super.testFile);

  /// The share of pixels allowed to differ, 0..1.
  static const double budget = 0.01;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= budget) return true;
    throw FlutterError(
      'The screenshot ${golden.pathSegments.last} differs from its reference '
      'in ${(result.diffPercent * 100).toStringAsFixed(2)}% of its pixels, '
      'past the ${(budget * 100).toStringAsFixed(2)}% a live status line and '
      'the rasteriser\'s own edges are allowed. Regenerate with '
      '--update-goldens once the change is the intended one.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Uri testFile = (goldenFileComparator as LocalFileComparator).basedir
      .resolve('tutorial_screenshots_test.dart');
  goldenFileComparator = _TolerantGoldens(testFile);

  bool fontsLoaded = false;
  setUpAll(() async {
    fontsLoaded = await _loadFonts();
  });

  /// Starts the application and waits until it has a document and a frame.
  ///
  /// **Explicit pumps, never `pumpAndSettle`.** The viewport asks for a
  /// frame from inside its own frame, so the tree never goes quiet — the
  /// same reason every other whole-screen test in this suite pumps by hand.
  /// The `runAsync` hops are the two pieces of genuine asynchrony: opening
  /// the device, and `decodeImageFromPixels` turning a rasterised frame into
  /// something Flutter can paint.
  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = _window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        // The application's own theme, which `ModelerApp` sets in a real
        // build — a screenshot in Flutter's default lavender would be a
        // picture of a modeller nobody has.
        theme: modelerTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ModelerScreen(
          autosaveStorage: _NullBinaryStorage(),
          settingsStorage: _MemorySettings(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    // A second round: the first frame is rasterised during the pump above,
    // and the image it decodes into only reaches the tree on the one after.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }

  /// Switches to [mode] through the real mode switcher and settles.
  Future<void> switchTo(WidgetTester tester, ModelerMode mode) async {
    // By tooltip, not by icon: an outliner row carries the same hexagon the
    // Mesh segment does, and a finder on the glyph alone matches both.
    await tester.tap(find.byTooltip(mode.label));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    // A picture of boxes is not a picture the tutorial can use, and saying
    // so is better than writing one out.
    expect(
      fontsLoaded,
      isTrue,
      reason: 'the SDK\'s own fonts were not found; see _sdkFonts',
    );
    await expectLater(
      find.byType(ModelerScreen),
      matchesGoldenFile('goldens/screens/$name.png'),
    );
  }

  /// The whole window including anything showing over it — a dialog lives in
  /// the app's own overlay, which is above `ModelerScreen` rather than
  /// inside it, so a finder on the screen alone would photograph the editor
  /// behind the dialog and not the dialog.
  Future<void> shootApp(WidgetTester tester, String name) async {
    expect(fontsLoaded, isTrue);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/screens/$name.png'),
    );
  }

  /// Taps something by tooltip and lets a dialog finish opening.
  Future<void> openByTooltip(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  group('every mode the editor offers', () {
    testWidgets('object mode, which is what a launch opens on', (
      WidgetTester tester,
    ) async {
      await launch(tester);
      await shoot(tester, 'object-mode');
    });

    for (final ModelerMode mode in ModelerMode.values) {
      if (!mode.ready || mode == ModelerMode.object) continue;
      testWidgets('${mode.name} mode', (WidgetTester tester) async {
        await launch(tester);
        await switchTo(tester, mode);
        await shoot(tester, '${mode.name}-mode');
      });
    }
  });

  group('every sub-mode inside a mode that has them', () {
    for (final MeshSubmode submode in MeshSubmode.values) {
      testWidgets('mesh · ${submode.name}', (WidgetTester tester) async {
        await launch(tester);
        await switchTo(tester, ModelerMode.mesh);
        // Inside the sub-mode switcher, because the label is a word the
        // panels and the rail also use — the segments carry a `Text` and no
        // tooltip, unlike the mode switcher above them.
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedButton<MeshSubmode>),
            matching: find.text(submode.label),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        await shoot(tester, 'mesh-${submode.name}');
      });
    }

    for (final AnimationSubmode submode in AnimationSubmode.values) {
      testWidgets('animation · ${submode.name}', (WidgetTester tester) async {
        await launch(tester);
        await switchTo(tester, ModelerMode.animation);
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedButton<AnimationSubmode>),
            matching: find.text(submode.label),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        await shoot(tester, 'animation-${submode.name}');
      });
    }
  });

  group('the screens a person is sent to', () {
    testWidgets('the start screen, which a first launch opens on', (
      WidgetTester tester,
    ) async {
      await launch(tester);
      await openByTooltip(
        tester,
        'Start screen — open a file or start a new project',
      );
      await shootApp(tester, 'start-screen');
    });

    testWidgets('settings', (WidgetTester tester) async {
      await launch(tester);
      await openByTooltip(
        tester,
        'Settings — navigation, keys, workspace, language',
      );
      await shootApp(tester, 'settings-screen');
    });

    testWidgets('the keyboard shortcuts', (WidgetTester tester) async {
      await launch(tester);
      await openByTooltip(tester, 'Keyboard shortcuts (?)');
      await shootApp(tester, 'shortcuts-screen');
    });
  });
}
