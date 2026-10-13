/// The files of the two project kinds that are more than one widget: a model
/// viewer on `Flutter3dView`, and a Flame game over a 3D layer.
///
/// **Each comes with the test it is held to.** `test/widget_test.dart` opens
/// the application on the software device `flutter test` has, and
/// `create_project_kinds_test.dart` in this package scaffolds every kind,
/// analyses it and runs that test, so a template that stops compiling
/// against the engine fails here and not in somebody's first hour.
///
/// **Named `widget_test.dart` on purpose**, as the game example's is:
/// `flutter create .` writes one of those, about a counter that does not
/// exist here, into any project that has no file by that name.
library;

/// Where a viewer project's starting model is written, and what its
/// `lib/main.dart` loads.
const String viewerModelPath = 'assets_src/model.glb';

// The Flutter imports, in two halves for the reason `project_template.dart`
// gives: this package is plain Dart, and a rule reads an import line in a
// template as one of its own.
const String _flutter =
    'package:'
    'flutter/';
const String _flutterTest =
    'package:'
    'flutter_test/flutter_test.dart';

/// Every kind's `analysis_options.yaml`: the lints, and the build and
/// platform directories left out as the SDK leaves them, so the first
/// `flutter analyze` does not rewrite the file it just read.
const String analysisOptions = '''
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - build/**
    - android/**
    - ios/**
    - web/**
    - windows/**
    - macos/**
    - linux/**
''';

/// The pubspec every kind shares, around its own [dependencies].
String _pubspec(String name, String description, String dependencies) =>
    '''
name: $name
description: "$description"
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ">=3.12.0 <4.0.0"
  flutter: ">=3.44.0"

dependencies:
  flutter:
    sdk: flutter
$dependencies
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
''';

/// What both READMEs say about running, after their first paragraph.
const String _running = '''
```sh
flutter create --platforms=macos,web .   # adds the platform folders, leaves the rest
flutter pub get
flutter run -d macos                     # or -d chrome
flutter test                             # opens the app on the software device
```

On macOS and iOS, add `FLTEnableFlutterGPU` and `FLTEnableImpeller`, both
`<true/>`, to `Runner/Info.plist`. Without them the app falls back to the
software renderer and says so in the console. In a browser it draws through
WebGL2, or WebGPU where the browser has it.
''';

/// The `scene` kind's test: the sphere's `Scene3D` opened on the software
/// device, and the sphere in it.
String sceneTest(String name) =>
    '''
/// The sphere opened on the software device `flutter test` has.
///
///     flutter test
library;

import '${_flutter}material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import '$_flutterTest';
import 'package:$name/main.dart';

void main() {
  testWidgets('the scene opens with the sphere in it', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(160, 120)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Game()));
    for (var i = 0; i < 100 && _meshes(tester).isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(find.byType(DidNotStart), findsNothing);
    expect(_meshes(tester), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

List<MeshNode> _meshes(WidgetTester tester) {
  final surface = find.byType(SceneSurface);
  if (surface.evaluate().isEmpty) return const <MeshNode>[];
  return tester.widget<SceneSurface>(surface).scene.meshes.toList();
}
''';

/// A model viewer: [viewerModelPath] on a stand of light, turned by a drag
/// and brought closer by a pinch or a scroll.
Map<String, String> viewerTemplate(String name) => <String, String>{
  'pubspec.yaml': _pubspec(name, 'A model viewer on flutter3d.', '''
  flutter3d: ^1.0.0-rc.1
  flutter3d_app: ^1.0.0-rc.1
'''),
  'analysis_options.yaml': analysisOptions,
  'lib/main.dart':
      '''
/// A model you can turn: a drag swings round it, a pinch or a scroll
/// brings it closer.
///
/// **One `Flutter3dView`.** It opens the device (the GPU where it starts,
/// the software rasteriser where it does not), makes the renderer and the
/// loop, and owns the frame clock, focus and teardown; this file hands it a
/// camera, a light and the model, and moves the camera when you do.
library;

import 'dart:async';

import '${_flutter}gestures.dart';
import '${_flutter}material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const ViewerApp());

/// The model to show: a source under `assets_src/`. The build hook converts
/// it on every build; a debug run reads the source itself until it has.
/// Drop a `.glb` of your own beside it and name it here.
const String modelSource = '$viewerModelPath';

class ViewerApp extends StatelessWidget {
  const ViewerApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: '$name',
    debugShowCheckedModeBanner: false,
    home: Viewer(source: modelSource),
  );
}

class Viewer extends StatefulWidget {
  const Viewer({super.key, required this.source});

  /// What [modelSource] is for this viewer.
  final String source;

  @override
  State<Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<Viewer> {
  final CameraNode _camera = CameraNode(name: 'eye');
  late final OrbitController _orbit = OrbitController(
    _camera,
    distance: 3.2,
    yaw: 0.6,
    pitch: 0.3,
    minDistance: 1.0,
    maxDistance: 12.0,
  );

  /// The model as loaded, released with the viewer.
  ModelAsset? _model;

  /// Why the model is not there, said on screen.
  Object? _failed;

  /// The orbit's distance when a pinch began.
  double _pinchFrom = 1.0;

  @override
  void dispose() {
    _model?.dispose();
    super.dispose();
  }

  /// The light, the floor's colour and the model, once the view has a
  /// device to put them on.
  void _open(Flutter3dEngine engine) {
    engine.view.clearColor = LinearColor.fromSrgb(0.08, 0.09, 0.11, 1.0);
    engine.scene.add(
      // Lux: a bright overcast day, from above and in front.
      LightNode(name: 'sun', intensity: 3.0 * LightNode.defaultIntensity)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.5)),
    );
    unawaited(_load(engine));
  }

  Future<void> _load(Flutter3dEngine engine) async {
    try {
      final model = await ModelAsset.fromDocument(
        await loadModelAsset(widget.source),
        device: engine.device,
      );
      if (!mounted) {
        model.dispose();
        return;
      }
      // Any model, whatever unit its author worked in: fitted to a metre
      // and a half tall and centred where the camera looks.
      model.instantiateFitted(engine.scene, length: 1.5, axis: 1);
      setState(() => _model = model);
    } catch (error) {
      if (mounted) setState(() => _failed = error);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      Listener(
        onPointerSignal: (PointerSignalEvent event) {
          if (event is PointerScrollEvent) {
            _orbit.zoom(event.scrollDelta.dy > 0.0 ? 1.1 : 1.0 / 1.1);
          }
        },
        child: GestureDetector(
          onScaleStart: (ScaleStartDetails details) =>
              _pinchFrom = _orbit.distance,
          onScaleUpdate: (ScaleUpdateDetails details) {
            _orbit.rotate(details.focalPointDelta.dx, details.focalPointDelta.dy);
            if (details.pointerCount > 1) {
              _orbit.zoom(_pinchFrom / details.scale / _orbit.distance);
            }
          },
          child: Flutter3dView(
            camera: _camera,
            onCreated: _open,
            onBeforeFrame: (_) => _orbit.syncProjectionDepth(_camera),
            view: ViewSettings(
              placeholder: const ColoredBox(
                color: Color(0xFF14161A),
                child: Center(child: CircularProgressIndicator()),
              ),
              failure: (Object error) => DidNotStart(
                error,
                background: const Color(0xFF14161A),
                foreground: const Color(0xFFFF8A80),
              ),
            ),
          ),
        ),
      ),
      if (_failed case final failed?)
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Could not load \${widget.source}: \$failed',
              style: const TextStyle(color: Color(0xFFFF8A80)),
            ),
          ),
        ),
    ],
  );
}
''',
  'test/widget_test.dart':
      '''
/// The viewer opened on the software device `flutter test` has, and the
/// model arriving in its scene.
///
///     flutter test
library;

import '${_flutter}widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import '$_flutterTest';
import 'package:$name/main.dart';

void main() {
  testWidgets('the viewer opens and the model arrives in its scene', (
    WidgetTester tester,
  ) async {
    // A small window: the software rasteriser draws every pixel of it.
    tester.view
      ..physicalSize = const Size(160, 120)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ViewerApp());

    // The device opens and the model loads asynchronously.
    for (var i = 0; i < 100 && _meshes(tester).isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(find.byType(DidNotStart), findsNothing);
    expect(find.textContaining('Could not load'), findsNothing);
    expect(_meshes(tester), isNotEmpty, reason: 'the model never arrived');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// The meshes in the scene the view draws, none before it has one.
List<MeshNode> _meshes(WidgetTester tester) {
  final surface = find.byType(SceneSurface);
  if (surface.evaluate().isEmpty) return const <MeshNode>[];
  return tester.widget<SceneSurface>(surface).scene.meshes.toList();
}
''',
  'README.md':
      '''
# $name

A model viewer on flutter3d, made by `flutter3d create project --kind viewer`.
A drag turns the model, a pinch or a scroll brings it closer.

$_running
The model is `$viewerModelPath`, a stand-in made when the project was. Put a
model of your own in `assets_src/` (glTF, GLB, OBJ, STL or PLY; FBX and
`.blend` through `flutter3d convert`) and name it in `modelSource` in
`lib/main.dart`. The build hook converts everything under `assets_src/` into
`flutter3d_generated/` on every build, and the viewer fits whatever it loads
to a metre and a half tall.
''',
};

/// A Flame game over a 3D layer: a catcher Flame steers, orbs falling in
/// the scene, and a score Flame draws on top.
Map<String, String> arcadeTemplate(String name) => <String, String>{
  'pubspec.yaml': _pubspec(name, 'A Flame game over a flutter3d layer.', '''
  flame: ^1.38.2
  flame_flutter3d: ^1.0.0-rc.1
  flutter3d: ^1.0.0-rc.1
'''),
  'analysis_options.yaml': analysisOptions,
  'lib/main.dart':
      '''
/// A Flame game drawn over a 3D layer: catch the orbs as they fall.
///
/// **Flame on top, flutter3d underneath, one clock.** `Flutter3dFlameWidget`
/// draws the scene and puts Flame's `GameWidget` over it; the game owns its
/// world through `HasFlutter3d`, so the catcher, the orbs and the light are
/// built in `onOpen3d` and stepped in Flame's own `update`. Flame's
/// positions cross into the scene on a `BridgePlane`: a backdrop here, so
/// Flame's `y` grows down the screen as it always does and the orbs fall
/// down it in 3D.
///
/// The arrow keys move the catcher; so does a finger or the mouse.
library;

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart' show KeyboardEvents;
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import '${_flutter}material.dart';
import '${_flutter}services.dart';
import 'package:flutter3d/flutter3d.dart';

void main() => runApp(const ArcadeApp());

class ArcadeApp extends StatelessWidget {
  const ArcadeApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: '$name',
    debugShowCheckedModeBanner: false,
    home: ArcadeScreen(),
  );
}

class ArcadeScreen extends StatefulWidget {
  const ArcadeScreen({super.key});

  @override
  State<ArcadeScreen> createState() => _ArcadeScreenState();
}

class _ArcadeScreenState extends State<ArcadeScreen> {
  // Made once and kept: a game made in `build` starts again on every
  // rebuild and never draws a frame.
  final ArcadeGame _game = ArcadeGame();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Listener(
      // A listener rather than a gesture: it takes nothing from Flame,
      // which sits on top and still hears every pointer.
      onPointerDown: (PointerDownEvent event) =>
          _game.aimAt(event.localPosition),
      onPointerMove: (PointerMoveEvent event) =>
          _game.aimAt(event.localPosition),
      child: Flutter3dFlameWidget(game: _game),
    ),
  );
}

/// The game. Its world is its own: [onOpen3d] builds it on the device the
/// widget opened, and [update] plays it.
class ArcadeGame extends FlameGame with HasFlutter3d, KeyboardEvents {
  /// [seed] decides where the orbs fall, so a test sees the same game twice.
  ArcadeGame({int seed = 1}) : _random = math.Random(seed);

  /// Flame's `(x, y)` is the scene's `(x, -y, 0)`: a backdrop facing the
  /// camera, in metres.
  static final BridgePlane plane = BridgePlane.backdrop();

  /// How far either side of the middle the catcher goes, in metres.
  static const double halfWidth = 4.0;

  /// Where the catcher runs, in metres down Flame's screen.
  static const double catcherY = 3.0;

  /// Where the orbs start, in metres down Flame's screen.
  static const double spawnY = -4.5;

  /// How far from the catcher's middle an orb is still caught, in metres.
  static const double reach = 1.0;

  final math.Random _random;

  late final Object3dComponent catcher;
  final List<Object3dComponent> orbs = <Object3dComponent>[];
  final TextComponent hud = TextComponent(
    text: 'Catch the orbs',
    position: Vector2(16.0, 16.0),
  );

  int score = 0;
  int missed = 0;

  /// -1, 0 or 1 from the arrow keys.
  double _steer = 0.0;

  /// Where a finger or the mouse last asked the catcher to go, in metres.
  double? _aim;

  /// Seconds until the next orb.
  double _untilNext = 0.0;

  late DeviceMesh _orb;
  late RenderMaterial _orbMaterial;

  @override
  CameraNode createCamera3d() => CameraNode(name: 'eye')
    ..setPosition(0.0, 0.0, 10.0)
    ..lookAt(Vector3.zero());

  @override
  void onOpen3d() {
    clearColor = LinearColor.fromSrgb(0.04, 0.05, 0.09);
    scene.add(
      // About 14 500 lux: a bright overcast noon.
      LightNode(intensity: 14476.0)
        ..setLocalForward(Vector3(-0.3, -0.6, -1.0)),
    );
    catcher = Object3dComponent(
      node: MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(1.8, 0.3, 0.8)).build(),
        ),
        RenderMaterial(
          name: 'catcher',
          baseColor: LinearColor.fromSrgb(0.3, 0.6, 0.95, 1.0),
          roughness: 0.4,
        ),
      ),
      scene: scene,
      plane: plane,
      direction: SyncDirection.flameToScene,
      position: Vector2(0.0, catcherY),
    );
    // One mesh and one material for every orb: each is a node drawing them.
    _orb = DeviceMesh.upload(device, const SphereShape(radius: 0.3).build());
    _orbMaterial = RenderMaterial(
      name: 'orb',
      baseColor: LinearColor.fromSrgb(1.0, 0.62, 0.2, 1.0),
      metallic: 0.2,
      roughness: 0.3,
    );
    addAll(<Component>[catcher, hud]);
  }

  /// Asks the catcher to go under [screen], a point on the game's canvas.
  void aimAt(Offset screen) {
    if (!has3d) return;
    _aim = projector.onPlane(Vector2(screen.dx, screen.dy), plane)?.x;
  }

  @override
  void update(double dt) {
    if (has3d && isLoaded) _play(dt);
    super.update(dt);
  }

  void _play(double dt) {
    // The catcher: toward where it was asked, or along the keys.
    final x = catcher.position.x;
    final want = _aim ?? x + _steer;
    final step = (want - x).clamp(-8.0 * dt, 8.0 * dt);
    catcher.position.x = (x + step).clamp(-halfWidth, halfWidth);

    _untilNext -= dt;
    if (_untilNext <= 0.0) {
      _untilNext = 0.9;
      final orb = Object3dComponent(
        node: MeshNode(_orb, _orbMaterial),
        scene: scene,
        plane: plane,
        direction: SyncDirection.flameToScene,
        position: Vector2(
          (_random.nextDouble() * 2.0 - 1.0) * (halfWidth - 0.5),
          spawnY,
        ),
      );
      orbs.add(orb);
      add(orb);
    }

    // Faster as the score climbs.
    final fall = (3.0 + 0.1 * score) * dt;
    for (final orb in List<Object3dComponent>.of(orbs)) {
      orb.position.y += fall;
      final caught =
          orb.position.y >= catcherY - 0.3 &&
          orb.position.y <= catcherY + 0.3 &&
          (orb.position.x - catcher.position.x).abs() < reach;
      if (caught) score++;
      if (caught || orb.position.y > catcherY + 1.5) {
        if (!caught) missed++;
        orbs.remove(orb);
        orb.removeFromParent();
      }
    }
    hud.text = 'Score \$score    Missed \$missed';
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final left = keysPressed.contains(LogicalKeyboardKey.arrowLeft);
    final right = keysPressed.contains(LogicalKeyboardKey.arrowRight);
    _steer = (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0);
    if (_steer != 0.0) _aim = null;
    return KeyEventResult.handled;
  }
}
''',
  'test/widget_test.dart':
      '''
/// The game played with no window, and the application opened on the
/// software device `flutter test` has.
///
///     flutter test
library;

import 'package:flame_flutter3d/flame_flutter3d.dart';
import '${_flutter}widgets.dart';
import '$_flutterTest';
import 'package:$name/main.dart';

void main() {
  testWidgets('orbs fall, and the score or the misses count them', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 240)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = ArcadeGame();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Flutter3dFlameWidget(game: game),
      ),
    );

    // The device opens and Flame loads the game asynchronously.
    for (var i = 0; i < 100 && !(game.has3d && game.isLoaded); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(game.has3d, isTrue, reason: 'the 3D layer never opened');
    expect(game.scene.meshes, isNotEmpty);

    // Five seconds of play, a sixtieth at a time.
    for (var i = 0; i < 300; i++) {
      game.update(1 / 60);
    }
    expect(game.score + game.missed, greaterThan(0));
    expect(game.hud.text, contains('Score'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the application opens', (WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(320, 240)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ArcadeApp());
    await tester.pump();
    expect(find.byType(Flutter3dFlameWidget), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
''',
  'README.md':
      '''
# $name

A Flame game over a flutter3d layer, made by
`flutter3d create project --kind arcade`. Catch the orbs: the arrow keys move
the catcher, and so does a finger or the mouse.

$_running
Flame draws on top (the score) and flutter3d underneath (the catcher, the
orbs and the light), one clock between them. The game owns its world through
`HasFlutter3d`; `flame_flutter3d`'s README names the rest of the bridge:
physics contacts reaching Flame's collision callbacks, a chase camera, models
inside Flame's own canvas, particles and Tiled maps.

Models go in `assets_src/`; the build hook converts them into
`flutter3d_generated/` on every build.
''',
};
