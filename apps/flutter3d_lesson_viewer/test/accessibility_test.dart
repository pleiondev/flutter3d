/// The lesson viewer for a student who does not use a mouse, does not see
/// the screen, reads at a larger text size or asked the system for less
/// motion: every control has a name, the controls are reached by Tab in the
/// order they are read, the scene turns from the keyboard, a larger text
/// size breaks nothing, and the loading screen holds still when motion is
/// reduced.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_lesson_viewer/src/lesson_loading_screen.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart' show LessonPlayer;
import 'package:flutter3d_lesson_viewer/src/lesson_view.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 8,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

List<EntityDef> _steps() => <EntityDef>[
  EntityDef(
    type: 'edu_step',
    name: 'quiz',
    position: Vector3(0.0, 1.6, 3.0),
    properties: <String, Object?>{
      'caption': 'The housing comes off first',
      'check': <String, Object?>{
        'question': 'How many screws hold it?',
        'answers': <String>['4'],
        'attempts': 2,
      },
    },
  ),
  EntityDef(
    type: 'edu_step',
    name: 'inside',
    position: Vector3(1.0, 1.6, 3.0),
    properties: <String, Object?>{'caption': 'Inside'},
  ),
];

Widget _view(
  LessonPlayer player, {
  CameraNode? camera,
  double textScale = 1.0,
  bool disableAnimations = false,
}) {
  final device = _device();
  final renderer = Renderer.create(device: device);
  final scene = Scene();
  final eye = camera ?? CameraNode(name: 'eye');
  scene.add(eye);
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: LessonView(
          renderer: renderer,
          scene: scene,
          camera: eye,
          player: player,
        ),
      ),
    ),
  );
}

/// A small window at one physical pixel per logical one: the software
/// renderer draws every pumped frame at the window's physical size, and the
/// test default (2400 by 1800) costs seconds a frame for nothing these tests
/// read.
void _smallWindow(WidgetTester tester, [Size size = const Size(480, 360)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// What has keyboard focus, named the way a test can compare: the answer
/// field, a button by its tooltip, or a focus node by its debug label.
String _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return 'nothing';
  if (context.findAncestorWidgetOfExactType<TextField>() != null) {
    return 'answer field';
  }
  final tooltip = context.findAncestorWidgetOfExactType<Tooltip>();
  if (tooltip != null) return tooltip.message ?? 'tooltip';
  return FocusManager.instance.primaryFocus?.debugLabel ?? 'unnamed';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every control is labelled, large enough to tap, and its text '
      'has the contrast AA asks for', (tester) async {
    final semantics = tester.ensureSemantics();
    _smallWindow(tester);
    await tester.pumpWidget(_view(LessonPlayer(_steps())));
    await tester.pump();

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('the scene is a named control that says how to turn it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    _smallWindow(tester);
    await tester.pumpWidget(_view(LessonPlayer(_steps())));
    await tester.pump();

    final view = tester.getSemantics(find.bySemanticsLabel('Lesson view'));
    expect(view.hint, contains('Arrow keys'));
    expect(view.flagsCollection.isFocused, isNot(ui.Tristate.none));
    semantics.dispose();
  });

  testWidgets('the caption is a live region, so a screen reader reads the '
      'new step without being asked, and says where in the lesson it is', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final player = LessonPlayer(_steps());
    _smallWindow(tester);
    await tester.pumpWidget(_view(player));
    await tester.pump();

    final first = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Step 1 of 2')),
    );
    expect(first.flagsCollection.isLiveRegion, isTrue);
    expect(first.label, contains('The housing comes off first'));

    await tester.tap(find.byTooltip('Next step'));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Step 2 of 2')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Tab reaches the answer, the submit button, the step buttons '
      'and then the scene, in that order', (tester) async {
    _smallWindow(tester);
    await tester.pumpWidget(_view(LessonPlayer(_steps())));
    await tester.pump();

    final order = <String>[];
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(_focused());
    }
    // `Previous step` is disabled on the first step and so not a stop.
    expect(order, <String>[
      'answer field',
      'Submit answer',
      'Next step',
      'Lesson view',
    ]);
  });

  testWidgets('with the scene focused, the arrow keys turn the camera and '
      'plus and minus zoom it, and a ring shows where the focus is', (
    tester,
  ) async {
    final camera = CameraNode(name: 'eye');
    _smallWindow(tester);
    await tester.pumpWidget(
      _view(LessonPlayer(<EntityDef>[_steps().last]), camera: camera),
    );
    await tester.pump();
    expect(find.byKey(LessonView.focusRingKey), findsNothing);

    // Next step is disabled on a one-step lesson; Previous too: the first
    // stop is the scene.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focused(), 'Lesson view');
    expect(find.byKey(LessonView.focusRingKey), findsOneWidget);

    final before = camera.readWorldPosition().clone();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    final turned = camera.readWorldPosition().clone();
    expect((turned - before).length, greaterThan(0.01));
    expect(turned.length, closeTo(before.length, 1e-6), reason: 'a turn');

    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pump();
    final nearer = camera.readWorldPosition().length;
    expect(nearer, lessThan(turned.length));

    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.pump();
    expect(camera.readWorldPosition().length, greaterThan(nearer));
  });

  testWidgets('at three times the text size on a phone the caption, the '
      'question and the buttons still lay out', (tester) async {
    _smallWindow(tester, const Size(360, 640));

    await tester.pumpWidget(_view(LessonPlayer(_steps()), textScale: 3.0));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('The housing comes off first'), findsOneWidget);
    expect(find.text('How many screws hold it?'), findsOneWidget);
    expect(
      tester.getSize(find.text('The housing comes off first')).width,
      lessThanOrEqualTo(360.0),
    );
  });

  group('the loading screen', () {
    testWidgets('spins as usual', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: LessonLoadingScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Loading the lesson'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('holds still and says it is loading when motion is reduced', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: LessonLoadingScreen(),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('^Loading the lesson')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}
