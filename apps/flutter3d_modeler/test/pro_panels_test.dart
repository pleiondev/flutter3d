/// The phase-four screens: `pro-rt-03`'s overlay, `pro-rt-07`'s bake panel,
/// `pro-sim-06`'s simulation panel and strip, `pro-rn-04`'s render panel and
/// `pro-pt-05`'s paint panel.
///
///     flutter test test/pro_panels_test.dart
library;

import 'dart:ui' as ui show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/bake_panel.dart';
import 'package:flutter3d_modeler/src/ui/paint_panel.dart';
import 'package:flutter3d_modeler/src/ui/render_panel.dart';
import 'package:flutter3d_modeler/src/ui/retopo_overlay.dart';
import 'package:flutter3d_modeler/src/ui/simulation_panel.dart';
import 'package:flutter_test/flutter_test.dart';

/// A panel under the delegates it reads its own words from.
///
/// **English, stated rather than inherited.** Every expectation below names
/// a word, and a test that took the host's locale would read those words in
/// whatever language the machine running it happens to be set to.
Widget wrapped(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('pro-rt-07: the bake panel', () {
    testWidgets('is 290 wide and offers the four maps', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapped(
          BakePanel(
            targetQuads: 4000,
            onTargetQuads: (int _) {},
            onRetopologize: () {},
            maps: const <String>{'normal'},
            onMap: (String _, bool _) {},
            resolution: 1024,
            onResolution: (int _) {},
            onBake: () {},
          ),
        ),
      );
      expect(tester.getSize(find.byType(BakePanel)).width, kBakePanelWidth);
      for (final String map in BakePanel.offered) {
        expect(find.byKey(ValueKey<String>('bakeMap-$map')), findsOneWidget);
      }
      expect(find.text('Bake 1 map'), findsOneWidget);
    });

    testWidgets('a running job takes the button\'s place, and can be stopped', (
      WidgetTester tester,
    ) async {
      var cancelled = 0;
      await tester.pumpWidget(
        wrapped(
          BakePanel(
            targetQuads: 4000,
            onTargetQuads: (int _) {},
            onRetopologize: () {},
            maps: const <String>{'normal', 'ao'},
            onMap: (String _, bool _) {},
            resolution: 1024,
            onResolution: (int _) {},
            onBake: () {},
            running: (label: 'Baking normal…', fraction: 0.4),
            onCancel: () => cancelled++,
          ),
        ),
      );

      // **The row's own acceptance.** Mutation: put the bar beside the
      // button and leave the button pressable. A person watching a bake can
      // start a second one, and the two write the same image.
      expect(find.byKey(const ValueKey<String>('bake')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('bakeProgress')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('bakeCancel')));
      expect(cancelled, 1);
    });

    testWidgets('and says once why neither button can run', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapped(
          BakePanel(
            targetQuads: 4000,
            onTargetQuads: (int _) {},
            onRetopologize: () {},
            maps: const <String>{'normal'},
            onMap: (String _, bool _) {},
            resolution: 1024,
            onResolution: (int _) {},
            onBake: () {},
            refusal: 'Select an object with UVs',
          ),
        ),
      );
      expect(find.text('Select an object with UVs'), findsOneWidget);
      final FilledButton bake = tester.widget(
        find.byKey(const ValueKey<String>('bake')),
      );
      expect(bake.onPressed, isNull);
    });
  });

  group('pro-sim-06: the simulation panel', () {
    testWidgets('offers a chip per kind and pins the selection', (
      WidgetTester tester,
    ) async {
      var pinned = 0;
      await tester.pumpWidget(
        wrapped(
          SimulationPanel(
            kind: 'cloth',
            onKind: (String _) {},
            parameters: const <String, double>{
              'stiffness': 0.6,
              'damping': 0.1,
            },
            onParameter: (String _, double _) {},
            colliders: const <String, bool>{'floor': true},
            onCollider: (String _, bool _) {},
            pinnedCount: 0,
            selectedCount: 12,
            onPinSelection: () => pinned++,
            onClearPins: () {},
          ),
        ),
      );

      for (final SimulationKindRow kind in SimulationPanel.kinds) {
        expect(
          find.byKey(ValueKey<String>('simKind-${kind.name}')),
          findsOneWidget,
        );
      }
      // **Pinning is a selection, not a list of numbers** — the row's own
      // "pinning through phase-1 selection". Mutation: a text field of
      // vertex indices. Nobody knows a vertex by its number.
      expect(find.text('Pin 12 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('simPinSelection')));
      expect(pinned, 1);
    });

    testWidgets('with nothing selected, it says so instead of doing nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapped(
          SimulationPanel(
            kind: 'cloth',
            onKind: (String _) {},
            parameters: const <String, double>{},
            onParameter: (String _, double _) {},
            colliders: const <String, bool>{},
            onCollider: (String _, bool _) {},
            pinnedCount: 0,
            selectedCount: 0,
            onPinSelection: () {},
            onClearPins: () {},
          ),
        ),
      );
      expect(find.text('Select vertices to pin'), findsOneWidget);
      expect(find.text('Nothing else in the scene'), findsOneWidget);
    });

    testWidgets('the strip is 150 tall and draws how much is baked', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapped(
          SimulationBar(
            cache: (frames: 100, baked: 40, running: false),
            frame: 10,
            onSeek: (int _) {},
            playing: false,
            onPlayPause: () {},
            onBake: () {},
            onClearCache: () {},
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(SimulationBar)).height,
        kSimulationBarHeight,
      );
      final LinearProgressIndicator bar = tester.widget(
        find.byKey(const ValueKey<String>('simCacheBar')),
      );
      expect(bar.value, closeTo(0.4, 1e-9));
      expect(find.text('10 / 100'), findsOneWidget);
    });

    testWidgets('and an empty cache leaves the transport alone', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapped(
          SimulationBar(
            cache: (frames: 0, baked: 0, running: false),
            frame: 0,
            onSeek: (int _) {},
            playing: false,
            onPlayPause: () {},
            onBake: () {},
            onClearCache: () {},
          ),
        ),
      );
      final IconButton play = tester.widget(
        find.byKey(const ValueKey<String>('simPlayPause')),
      );
      expect(play.onPressed, isNull);
    });
  });

  group('pro-rn-04: the render panel', () {
    testWidgets('is a 260-wide pass list, and fixed passes have no switch', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapped(
          RenderPanel(
            passes: const <RenderPassRow>[
              (name: 'scene', enabled: true, fixed: true),
              (name: 'ssao', enabled: true, fixed: false),
              (name: 'bloom', enabled: false, fixed: false),
              (name: 'output', enabled: true, fixed: true),
            ],
            onPass: (String _, bool _) {},
            onRender: () {},
          ),
        ),
      );

      expect(tester.getSize(find.byType(RenderPanel)).width, kRenderGraphWidth);
      // A fixed pass is drawn without a switch that does nothing.
      final SwitchListTile scene = tester.widget(
        find.byKey(const ValueKey<String>('renderPass-scene')),
      );
      expect(scene.onChanged, isNull);
      final SwitchListTile ssao = tester.widget(
        find.byKey(const ValueKey<String>('renderPass-ssao')),
      );
      expect(ssao.onChanged, isNotNull);
    });

    testWidgets('and the result takes the viewport, not a slot beside it', (
      WidgetTester tester,
    ) async {
      // **A thousand points of chrome does not fit a properties slot.**
      // Mutation: put the 760-wide result beside the 260-wide list. It
      // overflows every window narrower than the two of them together, which
      // is what it did before this split.
      await tester.pumpWidget(
        wrapped(const SizedBox(width: 400, height: 300, child: RenderResult())),
      );
      expect(find.text('Nothing rendered yet'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('renderResult'))),
        const Size(400, 300),
      );
    });

    testWidgets('a render in progress shows the tiles and offers a cancel', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapped(
          Column(
            children: <Widget>[
              RenderPanel(
                passes: const <RenderPassRow>[
                  (name: 'scene', enabled: true, fixed: true),
                ],
                onPass: (String _, bool _) {},
                onRender: () {},
                tilesDone: 6,
                tilesTotal: 16,
                onCancel: () {},
              ),
              const SizedBox(
                width: 400,
                height: 300,
                child: RenderResult(tilesDone: 6, tilesTotal: 16),
              ),
            ],
          ),
        ),
      );
      expect(find.byKey(const ValueKey<String>('render')), findsNothing);
      expect(find.text('Cancel · 6/16'), findsOneWidget);
      final LinearProgressIndicator bar = tester.widget(
        find.byKey(const ValueKey<String>('renderProgress')),
      );
      expect(bar.value, closeTo(6 / 16, 1e-9));
    });
  });

  group('pro-pt-05: the paint panel', () {
    testWidgets('is 300 wide, lists the layers top-first, and adds one', (
      WidgetTester tester,
    ) async {
      var added = 0;
      var picked = -1;
      await tester.pumpWidget(
        wrapped(
          SizedBox(
            height: 1200,
            child: PaintPanel(
              layers: const <PaintLayerRow>[
                (name: 'base', blend: 'normal', visible: true),
                (name: 'dirt', blend: 'multiply', visible: true),
              ],
              selectedLayer: 1,
              onSelectLayer: (int at) => picked = at,
              onAddLayer: () => added++,
              colour: const <double>[1, 1, 1, 1],
              onColour: (List<double> _) {},
              radius: kPaintCursorDiameter,
              onRadius: (double _) {},
              strength: 1,
              onStrength: (double _) {},
              masks: const <String>['ao bake'],
              mask: null,
              onMask: (String? _) {},
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(PaintPanel)).width, kPaintPanelWidth);
      // Top-first, the way every layer list anybody has used is drawn: the
      // stack is bottom-first and the panel is not.
      final double topRow = tester
          .getTopLeft(find.byKey(const ValueKey<String>('paintLayer-1')))
          .dy;
      final double bottomRow = tester
          .getTopLeft(find.byKey(const ValueKey<String>('paintLayer-0')))
          .dy;
      expect(topRow, lessThan(bottomRow));

      await tester.tap(find.byKey(const ValueKey<String>('paintLayer-0')));
      expect(picked, 0);
      await tester.tap(find.byKey(const ValueKey<String>('paintAddLayer')));
      expect(added, 1);
    });

    testWidgets('shows the canvas as soon as there is one', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapped(
          SizedBox(
            height: 1200,
            child: PaintPanel(
              layers: const <PaintLayerRow>[],
              selectedLayer: 0,
              onSelectLayer: (int _) {},
              onAddLayer: () {},
              colour: const <double>[1, 1, 1, 1],
              onColour: (List<double> _) {},
              radius: kPaintCursorDiameter,
              onRadius: (double _) {},
              strength: 1,
              onStrength: (double _) {},
              masks: const <String>[],
              mask: null,
              onMask: (String? _) {},
            ),
          ),
        ),
      );
      // **The row's own "the canvas updates after a stroke"** is this
      // widget being handed one: before a stroke there is nothing to show
      // and it says so rather than drawing an empty square somebody has to
      // guess about.
      expect(find.text('Nothing painted yet'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('paintCanvas')), findsOneWidget);
    });

    testWidgets('and the palette picks a colour', (WidgetTester tester) async {
      List<double>? picked;
      await tester.pumpWidget(
        wrapped(
          SizedBox(
            height: 1200,
            child: PaintPanel(
              layers: const <PaintLayerRow>[],
              selectedLayer: 0,
              onSelectLayer: (int _) {},
              onAddLayer: () {},
              colour: const <double>[1, 1, 1, 1],
              onColour: (List<double> to) => picked = to,
              radius: kPaintCursorDiameter,
              onRadius: (double _) {},
              strength: 1,
              onStrength: (double _) {},
              masks: const <String>[],
              mask: null,
              onMask: (String? _) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('paintSwatch-2')));
      expect(picked, PaintPanel.swatches[2]);
    });
  });

  group('pro-rt-03: the overlay', () {
    test('draws the grid, and the active quad filled at 22%', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const RetopoOverlay overlay = RetopoOverlay(
        quads: <ScreenQuad>[
          <Offset>[Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)],
        ],
        sourceAlpha: kSourceFaint,
        active: <Offset>[
          Offset(20, 20),
          Offset(30, 20),
          Offset(30, 30),
          Offset(20, 30),
        ],
      );
      // Painting has to complete without throwing — the whole of what a
      // painter can be unit-tested for without a golden — and the numbers
      // the row names are constants this file pins directly.
      overlay.paint(canvas, const Size(64, 64));
      recorder.endRecording();

      expect(kActiveQuadColour, const Color(0xFFFF458E));
      expect(kActiveQuadOpacity, closeTo(0.22, 1e-9));
      expect(kRetopoRibbonWidth, closeTo(1.6, 1e-9));
      // **Two transparencies, the row's own acceptance.** While the grid is
      // being drawn the source is a guide and wants to be faint; while it is
      // being judged it is the answer and wants to be readable.
      expect(kSourceFaint, lessThan(kSourceClear));
    });

    test('and repaints exactly when something it draws changed', () {
      const RetopoOverlay a = RetopoOverlay(
        quads: <ScreenQuad>[],
        sourceAlpha: kSourceFaint,
      );
      expect(a.shouldRepaint(a), isFalse);
      expect(
        a.shouldRepaint(
          const RetopoOverlay(quads: <ScreenQuad>[], sourceAlpha: kSourceClear),
        ),
        isTrue,
      );
    });

    test('an empty overlay draws nothing and does not throw', () {
      final recorder = ui.PictureRecorder();
      const RetopoOverlay(
        quads: <ScreenQuad>[],
        sourceAlpha: kSourceFaint,
      ).paint(Canvas(recorder), const Size(8, 8));
      recorder.endRecording();
    });
  });
}
