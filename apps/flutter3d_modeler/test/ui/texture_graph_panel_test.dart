/// `TextureGraphPanel`: `mat-13`'s own node-graph editor over one material's
/// `TextureGraph`.
///
///     flutter test test/ui/texture_graph_panel_test.dart
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/job_button.dart';
import 'package:flutter3d_modeler/src/ui/texture_graph_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A 1×1 black PNG — enough for `Image.memory` to decode into something,
/// which is all a thumbnail test needs it to do.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YA'
  'AAAASUVORK5CYII=',
);

/// A red flat colour feeding `albedo`, plus a lone `Channels` node nothing
/// points at yet — small enough to read at a glance, big enough to carry a
/// link, an unlinked input, and two different node kinds' own hints.
TextureGraph _graph() => TextureGraph(
  nodes: <TextureNode>[
    ColorTextureNode(id: 1, value: Vector4(1, 0, 0, 1)),
    const OutputTextureNode(id: 2, result: 1, slot: 'albedo'),
    const ChannelsTextureNode(id: 3),
  ],
  // Explicit, and all at the same shallow `y` — the panel's own fixed
  // expanded height (`ModelerMetrics.propertiesMin`) leaves a viewer window
  // shorter than several stacked cards would need, and the default
  // grid-fallback layout `TextureGraphPanel` uses when a graph carries no
  // positions of its own would put the third node's own controls below that
  // window in a test's fixed-size surface. A person panning the real
  // `InteractiveViewer` would just scroll to it; a test asserting on a
  // specific control needs it on screen without panning first.
  positions: <int, (double, double)>{1: (20, 8), 2: (220, 8), 3: (420, 8)},
);

final class _Calls {
  (String kind, Map<String, Object?> fields, (double, double) position)? addNode;
  (int nodeId, String input, int from)? link;
  (int nodeId, String input)? unlink;
  (int nodeId, String field, Object? value)? setNodeField;
  (int nodeId, double x, double y)? moveNode;
  int? removedNodeId;
  var baked = false;
  var cancelled = false;
}

Future<_Calls> _pump(
  WidgetTester tester, {
  TextureGraph? graph,
  Map<int, Uint8List> thumbnails = const <int, Uint8List>{},
  double? bakeProgress,
  bool initiallyExpanded = false,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(
        body: TextureGraphPanel(
          graph: graph ?? _graph(),
          thumbnails: thumbnails,
          bakeProgress: bakeProgress,
          initiallyExpanded: initiallyExpanded,
          onAddNode: (kind, fields, position) => calls.addNode = (kind, fields, position),
          onLink: (nodeId, input, from) => calls.link = (nodeId, input, from),
          onUnlink: (nodeId, input) => calls.unlink = (nodeId, input),
          onSetNodeField: (nodeId, field, value) =>
              calls.setNodeField = (nodeId, field, value),
          onMoveNode: (nodeId, x, y) => calls.moveNode = (nodeId, x, y),
          onRemoveNode: (nodeId) => calls.removedNodeId = nodeId,
          onBake: () => calls.baked = true,
          onCancelBake: () => calls.cancelled = true,
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  group('collapsed by default', () {
    testWidgets('shows only the header, at row height', (tester) async {
      await _pump(tester);

      expect(find.text('Texture graph'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);

      final size = tester.getSize(
        find.byKey(const ValueKey<String>('textureGraphPanel')),
      );
      expect(size.height, ModelerMetrics.row);
    });

    testWidgets('tapping the header expands it', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey<String>('textureGraphPanelHeader')));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('tapping again collapses it back', (tester) async {
      await _pump(tester);
      final header = find.byKey(const ValueKey<String>('textureGraphPanelHeader'));
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);

      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });
  });

  group('initiallyExpanded', () {
    testWidgets('starts open when asked to', (tester) async {
      await _pump(tester, initiallyExpanded: true);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });

  group('nodes and links', () {
    testWidgets('every node draws its own card, named by its kind', (
      tester,
    ) async {
      await _pump(tester, initiallyExpanded: true);

      expect(find.byKey(const ValueKey<String>('textureNode-1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('textureNode-2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('textureNode-3')), findsOneWidget);
      expect(find.text('color'), findsOneWidget);
      expect(find.text('output'), findsOneWidget);
      expect(find.text('channels'), findsOneWidget);
    });

    testWidgets('a node with a thumbnail shows Image.memory; one without a placeholder', (
      tester,
    ) async {
      await _pump(
        tester,
        initiallyExpanded: true,
        thumbnails: <int, Uint8List>{1: _onePixelPng},
      );

      expect(
        find.byKey(const ValueKey<String>('textureNodeThumbnail-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('textureNodeThumbnailPlaceholder-2')),
        findsOneWidget,
      );
    });

    testWidgets('the graph draws a CustomPaint for its links', (tester) async {
      await _pump(tester, initiallyExpanded: true);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('an already-wired input shows an unlink affordance', (
      tester,
    ) async {
      await _pump(tester, initiallyExpanded: true);
      expect(
        find.byKey(const ValueKey<String>('textureNodeUnlink-2-result')),
        findsOneWidget,
      );
      // The unwired Channels node has no such button for its own input.
      expect(
        find.byKey(const ValueKey<String>('textureNodeUnlink-3-source')),
        findsNothing,
      );
    });

    testWidgets('tapping unlink calls onUnlink with the right node and input', (
      tester,
    ) async {
      final calls = await _pump(tester, initiallyExpanded: true);
      await tester.tap(find.byKey(const ValueKey<String>('textureNodeUnlink-2-result')));

      expect(calls.unlink, (2, 'result'));
    });

    testWidgets('tapping an output then a compatible input calls onLink', (
      tester,
    ) async {
      final calls = await _pump(tester, initiallyExpanded: true);

      await tester.tap(find.byKey(const ValueKey<String>('textureNodeOutput-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('textureNodeInput-3-source')));
      await tester.pump();

      expect(calls.link, (3, 'source', 1));
    });

    testWidgets('tapping the same output twice disarms it — no link follows', (
      tester,
    ) async {
      final calls = await _pump(tester, initiallyExpanded: true);

      await tester.tap(find.byKey(const ValueKey<String>('textureNodeOutput-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('textureNodeOutput-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('textureNodeInput-3-source')));
      await tester.pump();

      expect(calls.link, isNull);
    });

    testWidgets('tapping a node\'s delete icon calls onRemoveNode with its id', (
      tester,
    ) async {
      final calls = await _pump(tester, initiallyExpanded: true);
      await tester.tap(find.byKey(const ValueKey<String>('textureNodeDelete-3')));

      expect(calls.removedNodeId, 3);
    });
  });

  group('dragging a node', () {
    testWidgets('reports a moved position through onMoveNode', (tester) async {
      final calls = await _pump(tester, initiallyExpanded: true);
      final header = find.byKey(const ValueKey<String>('textureNodeHeader-1'));
      expect(header, findsOneWidget);

      await tester.drag(header, const Offset(30, 15));
      await tester.pump();

      expect(calls.moveNode, isNotNull);
      expect(calls.moveNode!.$1, 1);
      final (double startX, double startY) = _graph().positions[1]!;
      expect(calls.moveNode!.$2, closeTo(startX + 30, 0.5));
      expect(calls.moveNode!.$3, closeTo(startY + 15, 0.5));
    });
  });

  group('hints', () {
    testWidgets('an EnumHint field (channel) shows a dropdown and reports a pick', (
      tester,
    ) async {
      final calls = await _pump(tester, initiallyExpanded: true);
      expect(find.byType(DropdownButton<String>), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      // Node 3 is the Channels node, defaulted to channel "r" — pick "g".
      await tester.tap(find.text('g').last);
      await tester.pumpAndSettle();

      expect(calls.setNodeField, (3, 'channel', 'g'));
    });

    testWidgets('a ColorHint field cycles a swatch and reports a value', (
      tester,
    ) async {
      final calls = await _pump(tester, initiallyExpanded: true);
      // Node 1's own `value` hint (a ColorHint) is wrapped in this key by
      // `_NodeCard`, one per node id and field name.
      final hint = find.byKey(const ValueKey<String>('textureNodeHint-1-value'));
      expect(hint, findsOneWidget);
      await tester.tap(
        find.descendant(of: hint, matching: find.byType(GestureDetector)),
      );
      await tester.pump();

      expect(calls.setNodeField, isNotNull);
      expect(calls.setNodeField!.$1, 1);
      expect(calls.setNodeField!.$2, 'value');
    });
  });

  group('adding a node', () {
    testWidgets('picking a kind from the menu calls onAddNode with its defaults', (
      tester,
    ) async {
      final calls = await _pump(tester, initiallyExpanded: true);

      await tester.tap(find.byKey(const ValueKey<String>('textureGraphAddNode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('noise').last);
      await tester.pumpAndSettle();

      expect(calls.addNode, isNotNull);
      expect(calls.addNode!.$1, 'noise');
      expect(calls.addNode!.$2, defaultTextureNodeFields('noise'));
    });
  });

  group('baking', () {
    testWidgets('shows the bake label idle, and starts on a tap', (
      tester,
    ) async {
      final calls = await _pump(tester, initiallyExpanded: true);

      expect(find.text('Запечь 2048²'), findsOneWidget);
      await tester.tap(find.byType(JobButton));
      expect(calls.baked, isTrue);
    });

    testWidgets('shows progress while a bake job is active, not the label', (
      tester,
    ) async {
      await _pump(tester, initiallyExpanded: true, bakeProgress: 0.42);

      expect(find.text('Запечь 2048²'), findsNothing);
      expect(find.text('42%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('cancels, not starts, while active', (tester) async {
      final calls = await _pump(tester, initiallyExpanded: true, bakeProgress: 0.5);

      await tester.tap(
        find.descendant(of: find.byType(JobButton), matching: find.byIcon(Icons.close)),
      );
      expect(calls.cancelled, isTrue);
      expect(calls.baked, isFalse);
    });

    testWidgets('re-enables the idle button once progress clears', (
      tester,
    ) async {
      final calls = _Calls();
      var progress = 0.6;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            theme: modelerTheme(),
            home: Scaffold(
              body: TextureGraphPanel(
                graph: _graph(),
                initiallyExpanded: true,
                bakeProgress: progress == 0 ? null : progress,
                onAddNode: (kind, fields, position) {},
                onLink: (nodeId, input, from) {},
                onUnlink: (nodeId, input) {},
                onSetNodeField: (nodeId, field, value) {},
                onMoveNode: (nodeId, x, y) {},
                onRemoveNode: (nodeId) {},
                onBake: () => calls.baked = true,
                onCancelBake: () => setState(() => progress = 0),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byType(JobButton), matching: find.byIcon(Icons.close)),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Запечь 2048²'), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton));
      expect(calls.baked, isTrue);
    });
  });
}
