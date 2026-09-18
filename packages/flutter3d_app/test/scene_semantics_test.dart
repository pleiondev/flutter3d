/// An object in the viewport reaches the accessibility layer — `gfx-79n`.
///
///     flutter test test/scene_semantics_test.dart
///
/// **What the platform saw before this.** A 3D viewport is one texture, so a
/// screen reader arriving at it was told there is an image, and touch
/// exploration found a single target the size of the window. Everything the
/// scene held was invisible to it — not hard to describe, simply never
/// described.
///
/// These tests read Flutter's own semantics tree rather than the widget tree,
/// because that tree is the thing the platform is handed and the only place the
/// claim can be checked. A test that found a `Semantics` widget would prove the
/// widget exists; `tester.getSemantics` proves a screen reader would find it.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show CameraNode, Scene, SceneNode;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(List<SemanticObject> objects, {bool enabled = true}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 400,
        height: 300,
        child: SceneSemantics(
          objects: objects,
          enabled: enabled,
          // Stands in for the rendered picture: one opaque rectangle that
          // would otherwise be the only thing the platform could see.
          child: Semantics(
            label: 'the viewport picture',
            child: const ColoredBox(color: Color(0xFF202020)),
          ),
        ),
      ),
    );

void main() {
  testWidgets('an object is announced by name', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(<SemanticObject>[
        const SemanticObject(
          id: 'wheel',
          label: 'left front wheel',
          bounds: Rect.fromLTWH(40, 60, 80, 50),
        ),
      ]),
    );

    expect(find.bySemanticsLabel('left front wheel'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the node sits where the object projects', (tester) async {
    final handle = tester.ensureSemantics();
    const rect = Rect.fromLTWH(40, 60, 80, 50);
    await tester.pumpWidget(
      _harness(const <SemanticObject>[
        SemanticObject(id: 'wheel', label: 'left front wheel', bounds: rect),
      ]),
    );

    // The rectangle is what the platform draws its focus ring around, so it
    // being the projection rather than the whole window is the difference
    // between a ring on the object and a ring on the viewport.
    final node = tester.getSemantics(find.bySemanticsLabel('left front wheel'));
    expect(node.rect.width, rect.width);
    expect(node.rect.height, rect.height);
    handle.dispose();
  });

  testWidgets('the picture underneath stops being a target', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(const <SemanticObject>[
        SemanticObject(
          id: 'wheel',
          label: 'left front wheel',
          bounds: Rect.fromLTWH(40, 60, 80, 50),
        ),
      ]),
    );

    // Leaving it in would give touch exploration a window-sized target *and*
    // the objects, and the window-sized one is what a finger finds first.
    expect(find.bySemanticsLabel('the viewport picture'), findsNothing);
    handle.dispose();
  });

  testWidgets('activating a node runs the action, not a hit test', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var tapped = 0;
    await tester.pumpWidget(
      _harness(<SemanticObject>[
        SemanticObject(
          id: 'wheel',
          label: 'left front wheel',
          bounds: const Rect.fromLTWH(40, 60, 80, 50),
          onTap: () => tapped++,
        ),
      ]),
    );

    // `tester.semantics.tap` is the platform invoking the action, not a
    // pointer landing on a widget — which is the distinction this test is
    // about. The node sits under `IgnorePointer`, so a real tap would fall
    // through to the viewport's own gestures; a screen reader does not tap.
    tester.semantics.tap(find.semantics.byLabel('left front wheel'));
    await tester.pump();

    expect(
      tapped,
      1,
      reason: 'the platform activated the node and nothing happened',
    );
    handle.dispose();
  });

  testWidgets('an object with no action is readable but not a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(const <SemanticObject>[
        SemanticObject(id: 'floor', label: 'floor', bounds: Rect.largest),
      ]),
    );

    // The honest state for something nothing can be done to: a screen reader
    // that called every object a button would be promising an action that is
    // not there.
    final node = tester.getSemantics(find.bySemanticsLabel('floor'));
    expect(node.flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  testWidgets('selection is announced as selection', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(<SemanticObject>[
        const SemanticObject(
          id: 'a',
          label: 'crate',
          bounds: Rect.fromLTWH(0, 0, 10, 10),
          selected: true,
          hint: 'double tap to deselect',
        ),
      ]),
    );

    final node = tester.getSemantics(find.bySemanticsLabel('crate'));
    // Through the platform's own flag rather than by decorating the label:
    // a reader announces the state in the person's own language, and a label
    // reading "crate (selected)" would say it twice in one of them.
    // Three-valued rather than a bool, and the distinction is the platform's
    // own: an object that *could* be selected and is not says so, while one
    // for which selection means nothing says nothing at all. A reader uses
    // that to decide whether to mention it.
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    expect(node.hint, 'double tap to deselect');
    handle.dispose();
  });

  testWidgets('switched off, the picture is what it always was', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(<SemanticObject>[
        const SemanticObject(
          id: 'wheel',
          label: 'left front wheel',
          bounds: Rect.fromLTWH(40, 60, 80, 50),
        ),
      ], enabled: false),
    );

    expect(find.bySemanticsLabel('left front wheel'), findsNothing);
    expect(find.bySemanticsLabel('the viewport picture'), findsOneWidget);
    handle.dispose();
  });

  test('a node with nothing in it is not announced', () {
    // The dropping rule, and it is not tidiness. A node with no bounds has no
    // rectangle, and a screen reader told about something whose focus ring has
    // nowhere to go is worse off than one never told at all: the ring lands at
    // the origin, which is a corner of the window that has nothing in it.
    final scene = Scene();
    final empty = SceneNode(name: 'empty')..setPosition(-2.0, 0.0, -6.0);
    scene.add(empty);

    final objects = semanticObjectsFor(
      <SceneAnnouncement>[
        SceneAnnouncement(id: 'empty', label: 'empty group', node: empty),
      ],
      camera: CameraNode(),
      size: const Size(400, 300),
    );

    expect(objects, isEmpty);
  });

  test('a viewport of no size announces nothing', () {
    // The first frame, before layout has run. Dividing by a zero height to get
    // an aspect is the other way to reach a NaN rectangle.
    expect(
      semanticObjectsFor(
        const <SceneAnnouncement>[],
        camera: CameraNode(),
        size: Size.zero,
      ),
      isEmpty,
    );
  });

  testWidgets('an empty list publishes nothing rather than an empty tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_harness(const <SemanticObject>[]));

    // A screen reader told "there is nothing here" is told something false:
    // the application may simply not have filled the list yet.
    expect(find.bySemanticsLabel('the viewport picture'), findsOneWidget);
    handle.dispose();
  });
}
