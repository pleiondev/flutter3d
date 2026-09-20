/// `wg-01`'s full path: a level names a `widget_surface` entity, the bridge
/// resolves the widget it names from the application's own registry, the
/// scene draws a live surface for it, and a ray hitting that surface really
/// changes the widget drawn there.
library;

import 'package:flutter/material.dart' hide Matrix4;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

GraphicsDevice _device() => CpuDevice(
  width: 4,
  height: 4,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an unknown widget name reports an issue and builds nothing', (
    tester,
  ) async {
    final issues = <String>[];
    final visuals = WidgetSurfaceVisuals(
      Scene(),
      device: _device(),
      registry: const <String, WidgetBuilder>{},
      onIssue: (issue) => issues.add(issue.message),
    );

    final surface = visuals.add(
      EntityDef(
        type: 'widget_surface',
        name: 'panel-1',
        properties: {'widget': 'nope'},
      ),
    );

    expect(surface, isNull);
    expect(issues, hasLength(1));
    expect(issues.single, contains('nope'));
    expect(visuals.surfaces, isEmpty);
  });

  testWidgets('a widget_surface entity resolves its widget by name, and a ray '
      'hitting it changes what is drawn', (tester) async {
    final scene = Scene();
    final device = _device();
    var taps = 0;
    final visuals = WidgetSurfaceVisuals(
      scene,
      device: device,
      registry: <String, WidgetBuilder>{
        'counter-panel': (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const ColoredBox(color: Color(0xFF224466)),
        ),
      },
    );
    addTearDown(visuals.dispose);

    final entity = EntityDef(
      type: 'widget_surface',
      name: 'panel-1',
      position: Vector3(0.0, 1.0, 0.0),
      properties: const {
        'widget': 'counter-panel',
        'width': 2.0,
        'height': 1.0,
      },
    );

    final surface = visuals.add(entity);
    expect(surface, isNotNull);
    expect(visuals.surfaces, [surface]);
    expect(scene.meshes, contains(surface!.node));

    // The same raycast-then-`uvAt`-then-`dispatchAtUv` chain
    // `widget_surface_test.dart` already proves against `WidgetSurface`
    // directly — here it is proven again through the bridge, on a surface
    // this class built rather than one a test built by hand.
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, 1.0, 0.0), Vector3(2.0, 1.0, 0.1));
    final hit = RayHit();
    world.raycast(Vector3(0.0, 1.0, -5.0), Vector3(0.0, 0.0, 1.0), 20.0, hit);
    expect(hit.hit, isTrue);

    final uv = surface.uvAt(hit.point, epsilon: 0.06);
    expect(uv, isNotNull);

    const pointer = 4;
    surface.pipeline.announcePointer(pointer, added: true);
    surface.pipeline.dispatchAtUv(
      uv!,
      (local) => PointerDownEvent(pointer: pointer, position: local),
    );
    surface.pipeline.dispatchAtUv(
      uv,
      (local) => PointerUpEvent(pointer: pointer, position: local),
    );
    surface.pipeline.announcePointer(pointer, added: false);

    expect(taps, 1);
  });

  testWidgets('tickAll redraws every surface it built', (tester) async {
    final scene = Scene();
    final device = _device();
    final visuals = WidgetSurfaceVisuals(
      scene,
      device: device,
      registry: <String, WidgetBuilder>{
        'sign': (context) => const ColoredBox(color: Color(0xFF224466)),
      },
    );
    addTearDown(visuals.dispose);

    final a = visuals.add(
      EntityDef(
        type: 'widget_surface',
        name: 'a',
        properties: const {'widget': 'sign'},
      ),
    )!;
    final b = visuals.add(
      EntityDef(
        type: 'widget_surface',
        name: 'b',
        properties: const {'widget': 'sign'},
      ),
    )!;

    final beforeA = a.node.material.albedo;
    final beforeB = b.node.material.albedo;
    await tester.runAsync(visuals.tickAll);

    expect(a.node.material.albedo, isNot(same(beforeA)));
    expect(b.node.material.albedo, isNot(same(beforeB)));
  });

  testWidgets('dispose takes every surface out of the scene', (tester) async {
    final scene = Scene();
    final visuals = WidgetSurfaceVisuals(
      scene,
      device: _device(),
      registry: <String, WidgetBuilder>{
        'sign': (context) => const ColoredBox(color: Color(0xFF224466)),
      },
    );

    final surface = visuals.add(
      EntityDef(
        type: 'widget_surface',
        name: 'a',
        properties: const {'widget': 'sign'},
      ),
    )!;
    expect(scene.meshes, contains(surface.node));

    visuals.dispose();

    expect(scene.meshes, isNot(contains(surface.node)));
    expect(visuals.surfaces, isEmpty);
  });

  group('edu_annotation', () {
    testWidgets(
      'resolves attachTo against the given nodes and offsets from it, '
      'rather than being added to the scene directly',
      (tester) async {
        final scene = Scene();
        final anchor = SceneNode()..setPositionFrom(Vector3(3.0, 0.0, 0.0));
        scene.add(anchor);
        final visuals = WidgetSurfaceVisuals(
          scene,
          device: _device(),
          registry: <String, WidgetBuilder>{
            'torque-spec-card': (context) =>
                const ColoredBox(color: Color(0xFF224466)),
          },
        );
        addTearDown(visuals.dispose);

        final surface = visuals.add(
          EntityDef(
            type: 'edu_annotation',
            name: 'valve-cover-note',
            properties: const {
              'widget': 'torque-spec-card',
              'attachTo': 'valve-cover',
              'offset': [0.0, 0.5, 0.0],
            },
          ),
          nodes: {'valve-cover': anchor},
        );

        expect(surface, isNotNull);
        expect(visuals.surfaces, [surface]);
        expect(anchor.children, contains(surface!.node));
        expect(
          surface.node.parent,
          same(anchor),
          reason:
              'a child of the anchor, not a sibling placed at a world '
              'coordinate once',
        );
        expect(surface.node.readPosition(), Vector3(0.0, 0.5, 0.0));
      },
    );

    testWidgets(
      'moves with its anchor node, the way an annotation on a torn-down '
      'part has to',
      (tester) async {
        final scene = Scene();
        final anchor = SceneNode();
        scene.add(anchor);
        final visuals = WidgetSurfaceVisuals(
          scene,
          device: _device(),
          registry: <String, WidgetBuilder>{
            'card': (context) => const ColoredBox(color: Color(0xFF224466)),
          },
        );
        addTearDown(visuals.dispose);

        final surface = visuals.add(
          EntityDef(
            type: 'edu_annotation',
            name: 'note',
            properties: const {'widget': 'card', 'attachTo': 'part'},
          ),
          nodes: {'part': anchor},
        )!;

        anchor.setPositionFrom(Vector3(1.0, 2.0, 3.0));

        expect(
          surface.node.readWorldPosition(),
          Vector3(1.0, 2.0, 3.0),
          reason: 'the annotation is a child, so it travels with its anchor',
        );
      },
    );

    testWidgets('a missing attachTo is reported, not thrown', (tester) async {
      final issues = <String>[];
      final visuals = WidgetSurfaceVisuals(
        Scene(),
        device: _device(),
        registry: <String, WidgetBuilder>{
          'card': (context) => const ColoredBox(color: Color(0xFF224466)),
        },
        onIssue: (issue) => issues.add(issue.message),
      );

      final surface = visuals.add(
        EntityDef(
          type: 'edu_annotation',
          name: 'note',
          properties: const {'widget': 'card', 'attachTo': 'no-such-node'},
        ),
      );

      expect(surface, isNull);
      expect(issues, hasLength(1));
      expect(issues.single, contains('no-such-node'));
      expect(visuals.surfaces, isEmpty);
    });

    testWidgets('an unknown widget name is reported before attachTo is even '
        'resolved', (tester) async {
      final issues = <String>[];
      final visuals = WidgetSurfaceVisuals(
        Scene(),
        device: _device(),
        registry: const <String, WidgetBuilder>{},
        onIssue: (issue) => issues.add(issue.message),
      );

      final surface = visuals.add(
        EntityDef(
          type: 'edu_annotation',
          name: 'note',
          properties: const {'widget': 'nope'},
        ),
      );

      expect(surface, isNull);
      expect(issues, hasLength(1));
      expect(issues.single, contains('nope'));
    });
  });
}
