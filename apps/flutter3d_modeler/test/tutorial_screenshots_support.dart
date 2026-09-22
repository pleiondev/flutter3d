/// What both screenshot files need: the fonts, the tolerance, and the
/// launching and settling a live editor takes.
///
/// Its own file rather than one test importing another, so neither is the
/// other's library and both read as what they are — a list of pictures.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kDoubleTapTimeout;
import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/main.dart' hide main;
import 'package:flutter3d_modeler/src/app_config.dart' show kOpeningReportFor;
import 'package:flutter3d_modeler/src/modeler_viewport.dart';
import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/ui/properties/object_row.dart';
import 'package:flutter3d_modeler/src/ui/properties/properties_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// The window every screenshot is taken in.
///
/// 1440×900 is what the design was drawn against and what `shell_test`
/// measures the frame at, so a picture lines up with the numbers that
/// document states.
const Size screenshotWindow = Size(1440, 900);

/// Answers every read with nothing and every write as if it landed, so a
/// screenshot run touches no real autosave slot.
final class NullBinaryStorage implements BinaryStorage {
  @override
  Future<Uint8List?> read(String name) async => null;

  @override
  Future<bool> write(String name, Uint8List contents) async => true;

  @override
  Future<void> remove(String name) async {}
}

/// A settings document in memory, so a screenshot run neither reads a
/// person's own preferences nor writes over them.
final class MemorySettings implements Storage {
  /// **Seeded, not empty** — `ux-42`. An empty settings store is a first
  /// launch, and a first launch now opens Quick Setup: every picture below
  /// would otherwise be a picture of that dialog. Seeded with the Full
  /// workspace for the same reason, since the tutorial's own cases walk
  /// through Mesh and Animation mode and a switcher showing three segments
  /// would contradict the sentence beside it.
  MemorySettings() {
    documents[SettingsStore.name] = jsonEncode(
      const ModelerSettings(
        quickSetupDone: true,
        workspace: Workspace.full,
        // And Home off: a picture of the editor should be of the editor, not
        // of the screen a launch opens over it. The case that wants Home
        // opens it by hand, which is also what a person does.
        showHomeAtLaunch: false,
      ).toJson(),
    );
  }

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

/// Where the SDK keeps the fonts a real build draws with.
///
/// **A screenshot with no fonts is a screenshot of boxes.** `flutter test`
/// loads none by default — every glyph, text and icon alike, is a filled
/// rectangle, which is right for a layout golden and useless for a picture
/// somebody is meant to read. The SDK ships Roboto and the Material icon
/// font in its own cache, and the Dart running this test *is* that cache's
/// own, so the path is derived rather than written down and works on
/// whichever machine or CI runner the SDK is installed on.
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
Future<bool> loadSdkFonts() async {
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
/// measurement of a real render and different every run; the software
/// rasteriser's own anti-aliasing moves a pixel at a silhouette edge. Both
/// are a handful of pixels out of 1.3 million, and a comparison that failed
/// on them would be one nobody could keep green — so it gets a budget, the
/// same way `cross_backend_test.dart` gives one to two backends drawing the
/// same scene.
///
/// The budget is deliberately small: a panel that moved, a label that
/// changed, a mode that stopped drawing its own rail are all far past it.
class TolerantGoldens extends LocalFileComparator {
  TolerantGoldens(super.testFile);

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
      "the rasteriser's own edges are allowed. Regenerate with "
      '--update-goldens once the change is the intended one.',
    );
  }
}

/// Installs [TolerantGoldens] for the file calling this.
void useTolerantGoldens(String testFileName) {
  final Uri testFile = (goldenFileComparator as LocalFileComparator).basedir
      .resolve(testFileName);
  goldenFileComparator = TolerantGoldens(testFile);
}

/// A few frames plus one real-time hop, which is what a live editor needs to
/// draw and decode one.
///
/// **Explicit pumps, never `pumpAndSettle`.** The viewport asks for a frame
/// from inside its own frame, so the tree never goes quiet — the same reason
/// every other whole-screen test in this suite pumps by hand.
Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  // **Past `kDoubleTapTimeout`, because a row can be double-clicked.**
  // `ux-14`'s own rename-in-place puts a double-tap recogniser on every
  // outliner row, and a single click arms a timer that waits three hundred
  // milliseconds to find out whether a second one is coming. A test that
  // disposes the tree before that timer fires fails on "a Timer is still
  // pending", which is what every screenshot taken after a click on the
  // object list started doing.
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
}

/// Starts the application and waits until it has a document and a frame.
///
/// [mcpPort] and [mcpSessionPath] are handed straight to [ModelerScreen]:
/// null leaves the agent server off, which is what every picture but the
/// agent panel's own wants. Zero asks the platform for a free port and
/// writes the session file into [mcpSessionPath], which is how a test can
/// connect a real client to the running editor.
Future<void> launchModeller(
  WidgetTester tester, {
  required bool fonts,
  int? mcpPort,
  String? mcpSessionPath,
}) async {
  // A picture of boxes is not a picture the tutorial can use, and saying so
  // is better than writing one out.
  expect(fonts, isTrue, reason: "the SDK's own fonts were not found");
  tester.view.physicalSize = screenshotWindow;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      // **Off, the way the real build has it** (`app_wiring.dart`). A test
      // that builds its own `MaterialApp` gets Flutter's DEBUG ribbon by
      // default, and every picture this tour has ever produced carried a red
      // band across the top-right corner, over the settings gear — a
      // photograph of something nobody running the application ever sees.
      debugShowCheckedModeBanner: false,
      // The application's own theme, which `ModelerApp` sets in a real
      // build — a screenshot in Flutter's default lavender would be a
      // picture of a modeller nobody has.
      theme: modelerTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ModelerScreen(
        autosaveStorage: NullBinaryStorage(),
        settingsStorage: MemorySettings(),
        mcpPort: mcpPort,
        mcpSessionPath: mcpSessionPath,
      ),
    ),
  );
  // Opening a device is genuine asynchronous work, and the frame it
  // rasterises only reaches the tree once `decodeImageFromPixels` has turned
  // it into something Flutter can paint — two hops, not one.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
  // **Past the opening card, so no picture is of one** — `ux-30`. "opened in
  // 340 ms" is drawn over the viewport's top-left corner for two seconds, and
  // the fake clock only moves when a test moves it: without this, whether a
  // given screenshot has a black measurement card in the corner of it comes
  // down to how many times that case happened to call [settleFrames].
  await tester.pump(kOpeningReportFor + const Duration(milliseconds: 10));
}

/// Switches to [mode] through the real mode switcher.
Future<void> switchMode(WidgetTester tester, ModelerMode mode) async {
  // By tooltip, not by icon: an outliner row carries the same hexagon the
  // Mesh segment does, and a finder on the glyph alone matches both.
  //
  // **Scrolled into view first.** Ten modes do not fit a laptop's top bar,
  // so `ModelerModeSwitcher` scrolls; a tap at a segment's own coordinates
  // without this hits whatever is drawn over it instead, which is how this
  // helper started failing the moment the fourth phase-four mode landed.
  final Finder segment = find.byTooltip(mode.label);
  await tester.ensureVisible(segment);
  await settleFrames(tester);
  await tester.tap(segment);
  await settleFrames(tester);
}

/// Switches the animation mode's own sub-mode.
Future<void> switchAnimationSubmode(
  WidgetTester tester,
  AnimationSubmode submode,
) async {
  final Finder segment = find.descendant(
    of: find.byType(SegmentedButton<AnimationSubmode>),
    matching: find.text(submode.label),
  );
  await tester.ensureVisible(segment);
  await settleFrames(tester);
  await tester.tap(segment);
  await settleFrames(tester);
}

/// Switches the mesh mode's own sub-mode.
Future<void> switchMeshSubmode(WidgetTester tester, MeshSubmode submode) async {
  final Finder segment = find.descendant(
    of: find.byType(SegmentedButton<MeshSubmode>),
    matching: find.text(submode.label),
  );
  await tester.ensureVisible(segment);
  await settleFrames(tester);
  await tester.tap(segment);
  await settleFrames(tester);
}

/// The editor, in the UV mode, with the cube a launch opens on held.
///
/// **Picked in Object mode first, which is where a person picks it.** A
/// launch selects nothing, and the UV mode — like Mesh, whose picture it
/// borrows — answers a click with an element of the held mesh rather than
/// with an object, so there is nothing in it to pick one *with*.
Future<void> openUvModeOnTheCube(
  WidgetTester tester, {
  required bool fonts,
}) async {
  await launchModeller(tester, fonts: fonts);
  await tester.tap(find.byType(ObjectRow).first);
  await settleFrames(tester);
  await switchMode(tester, ModelerMode.uv);
}

/// Scrolls the inspector to the held object's own "Levels of detail" row.
///
/// The panel is a lazy list and the row sits under the modifier stack, so on
/// a 900-tall window it is not merely off screen but not built.
Future<void> scrollToLodsRow(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey<String>('openLods')),
    120,
    scrollable: find
        .descendant(
          of: find.byType(PropertiesPanel),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await settleFrames(tester);
}

/// Presses the inspector's own "Open…" — screen 17 for whatever is held.
Future<void> openLodScreen(WidgetTester tester) async {
  await scrollToLodsRow(tester);
  await tester.tap(find.byKey(const ValueKey<String>('openLods')));
  await settleFrames(tester);
}

/// Marks every edge of the held mesh as a seam, the way a person would:
/// the Edge level, a box dragged round the whole picture, the rail's
/// scissors.
///
/// Every edge rather than a chosen few, because aiming a click at one edge
/// of a rasterised cube is a test of the picker and nothing that calls this
/// is about the picker. Twelve loose triangles is a poor unwrap and a
/// perfectly good one to count and to photograph.
Future<void> cutEveryEdge(WidgetTester tester) async {
  await switchMeshSubmode(tester, MeshSubmode.edge);
  final Rect picture = tester.getRect(find.byType(ModelerViewport));
  // From the corner the seam count is pinned to, on purpose: the card is a
  // label and the drag has to start on the picture under it. Mutation: take
  // the `IgnorePointer` off it in `ready_parts.dart`. The press goes to the
  // card, no box is drawn, and nothing is selected for the scissors to cut.
  final TestGesture drag = await tester.startGesture(
    picture.topLeft + const Offset(24, 24),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await drag.moveTo(picture.bottomRight - const Offset(24, 24));
  await tester.pump();
  await drag.up();
  await settleFrames(tester);
  await tester.tap(find.byIcon(Icons.content_cut_outlined));
  await settleFrames(tester);
}

/// Taps something by tooltip and lets a dialog finish opening.
Future<void> openByTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
  await settleFrames(tester);
}

/// Opens the export screen the way a person does: by clicking what the
/// status line says the model would export as.
///
/// Not a button — the top bar's own Export is a menu of formats, and the
/// full screen with the readiness list on it is reached from the sentence
/// about readiness itself (`ui-10`'s own "клик → диалог экспорта") or from
/// the keyboard.
Future<void> openExportScreen(WidgetTester tester) async {
  await tester.tap(
    find.textContaining(RegExp('ready to export|exports with|will not export')),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
  await settleFrames(tester);
}

/// The whole window including anything showing over it.
///
/// A dialog lives in the app's own overlay, which is above `ModelerScreen`
/// rather than inside it, so a finder on the screen alone would photograph
/// the editor behind the dialog and not the dialog.
Future<void> shootWindow(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/screens/$name.png'),
);
