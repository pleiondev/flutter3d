/// The viewport, drawn — not the camera arithmetic, the picture.
///
///     flutter test test/frame_test.dart
///
/// **The seam this covers is the one an application cannot see any other way.**
/// A stage can be assembled correctly and draw nothing: a light pointing away, a
/// camera inside the subject, a mesh uploaded with a layout the material does
/// not read. None of that is visible to a test that asserts on the scene graph,
/// and all of it is visible in eight hundred pixels.
///
/// Through `staging.dart`, because `no test builds its own world` in
/// `tool/structure.dart` says so and because a harness that built its own cube
/// would agree with any bug the application's cube has.
///
/// Counted pixels rather than a golden. A golden of a lit cube fails the day
/// somebody moves the fill light by five degrees and teaches nothing; what is
/// asserted here is that the subject was drawn, that it is lit from one side,
/// and that framing it put it in front of the camera.
// Draws real pixels: a scene through the software rasteriser, a reference
// picture, or both. Tagged so a run that only wants the logic skips the whole
// slow class at once:
//
//     very_good test -x golden
//
// Not optional in CI, which runs the suite without the flag.
@Tags(<String>['golden'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_mesh/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/display_modes.dart';
import 'package:flutter3d_modeler/src/ground_grid.dart';
import 'package:flutter3d_modeler/src/mesh_overlay_builder.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/profile_editing.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/material_studio_dialog.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 100;
const int _pixels = _width * _height;

/// What a frame is made of: how much of it is not the background, how bright
/// the brightest of that is, and how many distinct shades there are.
({int subject, int bright, int shades}) _describe(Uint8List rgba) {
  final shades = <int>{};
  var subject = 0;
  var bright = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final luminance =
        (rgba[i] * 30 + rgba[i + 1] * 59 + rgba[i + 2] * 11) ~/ 100;
    // The background is `#0E1112`, which lands at 17 through this weighting.
    // Anything above 24 is something that was drawn into it.
    if (luminance > 24) subject++;
    if (luminance > 120) bright++;
    shades.add(luminance >> 4);
  }
  return (subject: subject, bright: bright, shades: shades.length);
}

Future<Uint8List> _draw(
  GraphicsDevice device,
  Renderer renderer,
  ModelerStage stage,
) => _drawWith(device, renderer, stage, const RenderSettings());

Future<Uint8List> _drawWith(
  GraphicsDevice device,
  Renderer renderer,
  ModelerStage stage,
  RenderSettings settings,
) async {
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: stage.scene,
    views: stage.views(),
    settings: settings,
  );
  final pixels = await device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

void main() {
  test('the floor is drawn, in the colour the design named', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    stage.frameSubject();

    // The overlay the viewport builds every frame, built here the same way, so
    // that what this asserts is the chain from a grid line to a pixel rather
    // than a second arrangement that happens to agree with the first.
    final overlay = renderer.addContributor(
      MeshOverlay(
        vertexShader: renderer.debugLineVertexShader,
        fragmentShader: renderer.debugLineFragmentShader,
      ),
    );
    final look = stage.overlayView(_height.toDouble());
    overlay.lookFrom(
      eye: look.eye,
      right: look.right,
      up: look.up,
      pixel: look.pixel,
      perspective: look.perspective,
    );
    // A radius far past the model, so the whole visible floor is inside the
    // solid part of the fade. The fade itself is `ground_grid_test`'s subject
    // and is arithmetic; what is being asked here is whether a line the grid
    // wrote reaches a pixel *in the colour it was given*, and a line at half
    // strength cannot answer that.
    const grid = GroundGrid();
    grid.writeInto(overlay, eye: look.eye, fadeRadius: 1000);

    // Neutral composite, for the reason the normals view uses one: the exposure
    // and the tone curve are a picture of light, and `#2A3234` is not a light
    // value — it is a colour a design named. The viewport draws the same floor
    // through the lit settings and it comes out a little brighter, which is
    // deliberate and is argued in `MeshOverlay.asDrawn`.
    final rgba = await _drawWith(
      it.device,
      renderer,
      stage,
      const RenderSettings(tonemap: false, exposure: 1.0),
    );

    // 0x2A3234 is 42, 50, 52, and comes back as 43, 51, 53 — one level of an
    // eight-bit channel lost in the round trip through linear and back, which
    // is the width of the storage rather than an error in the arithmetic.
    // Nothing else in this scene is that colour: the background is 14, 18, 18
    // and the clay is far lighter.
    var lines = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if ((rgba[i] - 42).abs() <= 2 &&
          (rgba[i + 1] - 50).abs() <= 2 &&
          (rgba[i + 2] - 52).abs() <= 2) {
        lines++;
      }
    }

    // Two mutations, both of which this is the only test in the repository to
    // catch, and both of which were live in the overlay when it was written:
    // drop the index buffer `MeshOverlay._draw` binds, and nothing draws at all
    // — `draw` in this engine is always indexed, and a draw with no indices
    // bound is a legal, silent draw of nothing; and write the caller's colour
    // into the batch literally instead of through `asDrawn`, and the floor
    // comes back `#717B7D`, half again as bright as the design named. Every
    // test the overlay and the grid had passed under both, because all of them
    // read the batch and none of them asked whether anything drew it.
    expect(lines, greaterThan(20), reason: 'no grid line reached a pixel');
  });

  test('the mesh a project starts as is drawn as a wireframe', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    stage.frameSubject();
    final EditMesh? edit = stage.editMesh;
    expect(edit, isNotNull, reason: 'a new project is the cube, and has one');

    final overlay = renderer.addContributor(
      MeshOverlay(
        vertexShader: renderer.debugLineVertexShader,
        fragmentShader: renderer.debugLineFragmentShader,
      ),
    );
    final look = stage.overlayView(_height.toDouble());
    final colours = MeshOverlayColours();
    MeshOverlayBuilder(colours: colours).build(
      overlay,
      mesh: edit!,
      selection: Selection.empty(ElementLevel.vertex),
      meshVersion: 1,
      selectionVersion: 1,
      view: MeshOverlayView(
        eye: look.eye,
        right: look.right,
        up: look.up,
        pixel: look.pixel,
        perspective: look.perspective,
      ),
    );

    final rgba = await _drawWith(
      it.device,
      renderer,
      stage,
      const RenderSettings(tonemap: false, exposure: 1.0),
    );

    // The wire colour is a middle grey, and nothing else in this scene is: the
    // clay is warm and much lighter, the background is nearly black, and the
    // floor is not in this frame.
    final wire = <int>[
      (colours.wire.x * 255).round(),
      (colours.wire.y * 255).round(),
      (colours.wire.z * 255).round(),
    ];
    var edges = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if ((rgba[i] - wire[0]).abs() <= 2 &&
          (rgba[i + 1] - wire[1]).abs() <= 2 &&
          (rgba[i + 2] - wire[2]).abs() <= 2) {
        edges++;
      }
    }

    // Mutation: hand the builder a mesh and never register the overlay with
    // the renderer, which is what every test of the builder does — all of them
    // stay green, because all of them read the batch. The cube has twelve
    // edges and each of them is a line several pixels long.
    expect(
      edges,
      greaterThan(20),
      reason: 'no edge of the mesh reached a pixel',
    );
  });

  test('a +Y face in the normals view is the colour of a +Y normal', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    stage.frameSubject();
    // Straight down at the cube's top face, so the middle of the frame is a
    // face whose normal is exactly +Y and the answer is a number rather than a
    // range.
    lookFrom(stage.orbit, StandardView.top, seconds: 0.0);
    // `gfx-43n`: no swap. The mode is in the settings below, and the normal
    // it shows comes out of the buffer the scene pass writes.

    final rgba = await _drawWith(
      it.device,
      renderer,
      stage,
      settingsFor(ShadingMode.normals, const RenderSettings()),
    );

    // `(0, 1, 0)` encoded the way every normal buffer encodes one, half the
    // range either side of zero: 128, 255, 128. Mutation: leave the exposure at
    // the 1.6 a lit scene wants and this is 159, 255, 159; leave the tone curve
    // on as well and it is 137, 249, 137. Both look like a plausible green and
    // neither is the normal — which is the whole difficulty with a diagnostic
    // view that is nearly right.
    final at = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
    expect(rgba[at], closeTo(128, 2));
    expect(rgba[at + 1], closeTo(255, 2));
    expect(rgba[at + 2], closeTo(128, 2));
  });

  test('an orthographic picture does not change size as the camera moves '
      'back — view-04\'s own "орто не зависит от distance"', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    stage.frameSubject();
    lookFrom(stage.orbit, StandardView.front, seconds: 0.0);
    useLens(stage.camera, ViewLens.orthographic, stage.orbit);

    final near = await _draw(it.device, renderer, stage);
    final nearEye = stage.camera.readWorldPosition().clone();

    // Walked straight back along the view axis rather than zoomed: `zoom`
    // scales `orthoHeight` along with `distance` on purpose, which is a
    // person asking the model to look bigger or smaller. Setting `distance`
    // directly is a camera moving without anybody having asked for that —
    // `OrbitController.orthoHeight`'s own doc comment is explicit that an
    // orthographic picture must not answer that with a different size.
    stage.orbit.distance *= 4.0;
    stage.orbit.apply();

    final far = await _draw(it.device, renderer, stage);

    // The camera really did move — otherwise the picture matching itself
    // would prove nothing at all.
    expect(
      (stage.camera.readWorldPosition() - nearEye).length,
      greaterThan(1.0),
    );

    // A tolerance of two rather than an exact match: the light is a direction
    // and the cube's own silhouette does not move, but a lit material still
    // reads the eye position for its own specular term, and that has moved
    // even though nothing about the picture's own size has. Mutation: derive
    // the projection's height from `orbit.distance` on every frame instead of
    // reading the value `useLens` fixed in place, and the cube shrinks to a
    // quarter of its own width the moment the camera backs away — exactly the
    // shrink a perspective lens gives, and exactly what an orthographic one
    // must refuse to; a shrunk silhouette moves thousands of pixels this
    // tolerance does not absorb, not one.
    expect(far.length, near.length);
    var moved = 0;
    for (var i = 0; i < far.length; i++) {
      if ((far[i] - near[i]).abs() > 2) moved++;
    }
    expect(moved, 0, reason: 'the picture changed size or position');
  });

  test('the cube a project starts as is drawn, and it is lit', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    stage.frameSubject();

    final frame = _describe(await _draw(it.device, renderer, stage));

    // A framed cube seen from a three-quarter angle covers between a sixth and
    // two thirds of the viewport. Both bounds matter: too little is a cube
    // that did not draw or is far away, too much is a camera inside it.
    expect(
      frame.subject,
      greaterThan(_pixels ~/ 6),
      reason: 'the cube did not draw, or is not in front of the camera',
    );
    expect(
      frame.subject,
      lessThan(_pixels * 2 ~/ 3),
      reason: 'the camera is inside the cube, or the framing did not happen',
    );

    // **Lit from a direction, which is a stronger claim than "lit".** A `pbr`
    // material with no light on it at all still comes back bright here — the
    // renderer's neutral environment is what a material samples when nothing
    // else lights it — so a check for brightness passes on a scene with the
    // lights turned off, and the first version of this file made exactly that
    // mistake. What separates the two is the *spread*: with both lights at
    // zero the frame holds four bands of luminance and every drawn pixel is in
    // the bright one; with the key and the fill where `staging.dart` puts
    // them, it holds eight and a face is in shadow.
    expect(
      frame.shades,
      greaterThanOrEqualTo(6),
      reason: 'the faces are all one value, so no light has a direction',
    );
    expect(
      frame.subject - frame.bright,
      greaterThan(_pixels ~/ 100),
      reason: 'no face is in shadow: the key light is not reaching one side',
    );
  });

  test('the background is the one the design names, not the default', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    // Pushed far enough away that the corner pixel is background and nothing
    // else, without moving the camera off the subject.
    stage.orbit
      ..distance = 40
      ..apply();

    final rgba = await _draw(it.device, renderer, stage);

    // Top-left pixel. `#0E1112` through the composite, which tone maps: what
    // is asserted is the hue rather than the exact byte — blue above green
    // above red, all of them dark — because a flat dark background that had
    // gone grey or gone blue would both pass a "is it dark" check.
    final r = rgba[0];
    final g = rgba[1];
    final b = rgba[2];
    expect(r, lessThan(60), reason: 'the background is not dark');
    expect(g, greaterThanOrEqualTo(r));
    expect(b, greaterThanOrEqualTo(g));
  });

  test('orbiting changes the picture, and does not lose the subject', () async {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device);
    stage.frameSubject();

    final before = await _draw(it.device, renderer, stage);
    // A quarter turn, the way a drag of two hundred pixels would.
    stage.orbit
      ..rotate(200, 0)
      ..apply();
    final after = await _draw(it.device, renderer, stage);

    expect(
      after,
      isNot(equals(before)),
      reason: 'the camera moved and the frame did not follow it',
    );
    expect(
      _describe(after).subject,
      greaterThan(_pixels ~/ 6),
      reason: 'the subject left the view when the camera turned',
    );
  });

  group('the picture follows the document', () {
    // `ui-26`'s own claim, drawn rather than read off the scene graph:
    // `modeler_cubit_test.dart` already asks `sync.nodeOf` whether a node
    // exists after a command lands, which is a fact about the tree and not
    // about a pixel. This asks the rasteriser instead, through the same
    // `ModelerCubit` a screen drives, so a `SceneSync.apply` that ran and
    // uploaded the wrong thing — or that `_synced` simply stopped calling —
    // shows up as two identical frames rather than as a passing tree.
    test('a command that changes the document changes what is drawn', () async {
      final it = cpuTestDevice(width: _width, height: _height);
      final renderer = Renderer.create(device: it.device);
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'a',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );
      final history = ModelHistory(project);
      final stage = ModelerStage.fromProject(
        device: it.device,
        project: history.project,
      );
      stage.frameSubject();
      final cubit = ModelerCubit()
        ..opened(history, renderer: renderer, stage: stage);

      final before = _describe(await _draw(it.device, renderer, stage));

      // Scaling the one object up is a command like any other — it goes
      // through `ModelHistory.run` and then `ModelerCubit._synced`, the
      // same path a rename or an extrude takes.
      cubit
        ..ran(const SelectAll())
        ..ran(const ScaleBy(2.5));

      final after = _describe(await _draw(it.device, renderer, stage));

      // Mutation: comment out `now.stage.sync?.apply(now.project)` in
      // `ModelerCubit._synced`. The document doubles the object's size,
      // the history and the readiness both move on, and the picture stays
      // exactly the frame the cube was drawn at before — nothing else in
      // the repository draws this document twice and compares the pixels.
      expect(
        after.subject,
        greaterThan(before.subject),
        reason:
            'the object grew in the document and the picture did not grow '
            'with it',
      );
    });
  });

  group('the spike, drawn', () {
    // `mesh-01`'s last line: the half-edge cube with a face extruded, rendered
    // by the software rasteriser and held to a recorded picture. Everything
    // before this is arithmetic — the Euler characteristic, the volume — and
    // arithmetic cannot say that the mesh a person would see is the mesh the
    // operation built.
    test('a cube with one face extruded matches its reference', () async {
      final frame = await renderFrame(
        width: 240,
        height: 160,
        build: (FrameRequest request) {
          final stage = ModelerStage.build(device: request.device);
          // The stage's own cube, replaced by the extruded one: the scene, the
          // lights and the camera stay the application's, which is what
          // `no test builds its own world` is about, and only the geometry
          // under test changes.
          final subject = stage.subject as MeshNode;
          subject.mesh = DeviceMesh.upload(
            request.device,
            EditMesh.cuboid().extrudeFace(0, 0.5).toMeshData(),
          );
          stage.frameSubject();
          return (scene: stage.scene, camera: stage.camera);
        },
      );

      await expectMatchesGolden(frame, 'test/goldens/mesh-spike-extrude.png');
    });
  });

  group('the operations, drawn', () {
    // `mesh-33`: four fixtures from `flutter3d_mesh/testing.dart`, each one
    // the smallest shape that would *look* wrong if the operation under it
    // broke. Everything else about these operations is arithmetic — Euler
    // characteristics, volumes, counts — and arithmetic cannot say that a wall
    // is there, that a cut went in straight, that a pole closed, or that a rim
    // still shades hard.
    //
    // Zero tolerance, because the rasteriser is deterministic and these are
    // pictures of geometry rather than of lighting: a pixel that moved is a
    // vertex that moved.
    for (final subject in <(String, EditMesh Function())>[
      ('mesh-extrude', extrudedBox),
      ('mesh-loop-cut', cutCylinder),
      ('mesh-lathe', turnedProfile),
      ('mesh-sharp-vs-smooth', sharpAgainstSmooth),
    ]) {
      test('${subject.$1} matches its reference', () async {
        final frame = await renderFrame(
          width: 240,
          height: 160,
          build: (FrameRequest request) {
            final stage = ModelerStage.build(device: request.device);
            final node = stage.subject as MeshNode;
            node.mesh = DeviceMesh.upload(
              request.device,
              subject.$2().toMeshData(),
            );
            stage.frameSubject();
            return (scene: stage.scene, camera: stage.camera);
          },
        );

        await expectMatchesGolden(frame, 'test/goldens/${subject.$1}.png');
      });
    }
  });

  group('the phase-two operations, drawn', () {
    // `mesh-49`: four more fixtures from `flutter3d_mesh/testing.dart`, the
    // same shape `mesh-33`'s own group already established — bevel,
    // Catmull-Clark, a BSP boolean and a mirror, each already proven by
    // arithmetic in its own package test and now checked as a picture, which
    // is what catches a corner cap at the wrong valence, a subdivision that
    // pinched a pole, a boolean that bit into the wrong face, or a mirror
    // seam that never welded.
    for (final subject in <(String, EditMesh Function())>[
      ('mesh-bevel', bevelledCube),
      ('mesh-catmull-clark', subdividedCube),
      ('mesh-cube-minus-sphere', cubeMinusSphere),
      ('mesh-mirror-vase', mirroredVase),
    ]) {
      test('${subject.$1} matches its reference', () async {
        final frame = await renderFrame(
          width: 240,
          height: 160,
          build: (FrameRequest request) {
            final stage = ModelerStage.build(device: request.device);
            final node = stage.subject as MeshNode;
            node.mesh = DeviceMesh.upload(
              request.device,
              subject.$2().toMeshData(),
            );
            stage.frameSubject();
            return (scene: stage.scene, camera: stage.camera);
          },
        );

        await expectMatchesGolden(frame, 'test/goldens/${subject.$1}.png');
      });
    }
  });

  group('the skeleton overlay, drawn', () {
    // `anim-08`: the octahedra and crosses `DebugDrawGizmos.addSkeletonOverlay`
    // already draws, reached this time through `RenderSettings.debug` the way
    // the application would ask for them, rather than by calling the overlay
    // builder directly the way `debug_draw_test.dart` already does.
    //
    // **Built from a project, not a hand-assembled `Skeleton` — `view-27d`'s
    // own row.** The two joints and the mesh below are ordinary
    // `ModelObject`s, reaching the screen through `ModelerStage.fromProject`
    // and `SceneSync.apply` exactly the way a real rig would. This file used
    // to build the engine `Skeleton` itself and hand it straight to the
    // mesh node, which meant nothing here ever exercised `scene_sync.dart`'s
    // own skinning at all — a mutation that dropped its upload of
    // `VertexLayout.skinned`, or never hung a `Skeleton` off the mesh in the
    // first place, would have passed this test and every other one in this
    // suite.
    test('a two-joint rig built from a project matches its reference, and '
        'moving a joint actually deforms the mesh', () async {
      final it = cpuTestDevice(width: 240, height: 160);

      // The top four vertices ride the tip, the bottom four the root — a
      // real two-joint bind rather than the all-one-joint default every
      // other skinned mesh in this file draws with. A mesh bound wholly to
      // the root would look identical whether or not moving the *tip*
      // reached it at all, which is exactly the "disconnected socket" bug
      // this row fixes and this test is the one that would otherwise miss.
      final mesh = EditMesh.cuboid();
      mesh.beginStep();
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        if (mesh.positionOf(v).y > 0) {
          mesh.setSkin(
            v,
            VertexAttributes(
              joints: Vector4(1, 0, 0, 0),
              weights: Vector4(1, 0, 0, 0),
            ),
          );
        }
      }
      mesh.endStep();

      var project = ModelProject(
        objects: <ModelObject>[
          ModelObject(
            id: 1,
            name: 'root',
            geometry: const SocketGeometry(),
            transform: Matrix4.identity(),
          ),
          ModelObject(
            id: 2,
            name: 'tip',
            geometry: const SocketGeometry(),
            transform: Matrix4.translation(Vector3(0.0, 0.5, 0.0)),
            parent: 1,
          ),
          ModelObject(
            id: 3,
            name: 'cube',
            geometry: EditedGeometry(mesh),
            transform: Matrix4.identity(),
            skeletonIndex: 0,
          ),
        ],
        nextId: 4,
      );
      // Bind-pose inverse matrices from the joints' own rest transforms —
      // `poseOf`'s own job, the same arithmetic a real importer or
      // `SetRestPose` already trusts, rather than this test inverting two
      // matrices by hand a second way.
      final bindPose = poseOf(
        project,
        ProjectSkeleton(
          joints: <int>[1, 2],
          inverseBindMatrices: <Matrix4>[
            Matrix4.identity(),
            Matrix4.identity(),
          ],
        ),
      );
      project = project.copyWith(
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            joints: <int>[1, 2],
            inverseBindMatrices: <Matrix4>[
              for (final world in bindPose.worldMatrices())
                Matrix4.copy(world)..invert(),
            ],
          ),
        ],
      );

      final stage = ModelerStage.fromProject(
        device: it.device,
        project: project,
      );
      // A skinned mesh's own bounds describe the bind pose, so framing —
      // and `skinReach`, which pads it — has to come from the joints
      // instead; `SceneSync` sets that itself once the skeleton is built,
      // as part of the same pass `stage.frameSubject()` below reads.
      stage.frameSubject();
      final renderer = Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      );

      Future<RenderedFrame> draw() async {
        final result = renderer.render(
          width: 240,
          height: 160,
          scene: stage.scene,
          views: <RenderView>[
            RenderView(
              camera: stage.camera,
              clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
            ),
          ],
          settings: const RenderSettings(
            debug: DebugDrawOptions(skeletons: true),
          ),
        );
        final pixels = await it.device.readPixels(result.frame);
        expect(pixels, isNotNull, reason: 'the frame could not be read back');
        return (
          pixels: pixels!.buffer.asUint8List(),
          width: 240,
          height: 160,
          drawCalls: result.drawCalls,
        );
      }

      final rest = await draw();
      await expectMatchesGolden(rest, 'test/goldens/skeleton-overlay.png');

      // The tip, slid sideways — an ordinary edit through the same door a
      // drag or `PoseJoint` both use: a new `ModelObject` value for the
      // joint, nothing more. The root never moves, so a vertex still bound
      // to it stays exactly where it was; a vertex bound to the tip has to
      // follow, which is what turns a rigid slide of one joint into an
      // actual shear of the mesh rather than the whole cube sliding as one
      // block.
      final bentProject = project.withObject(
        project[2]!.copyWith(
          transform: Matrix4.translation(Vector3(0.3, 0.5, 0.0)),
        ),
      );
      stage.sync!.apply(bentProject);
      final bent = await draw();

      // Mutation: never build the engine `Skeleton` at all, or build it
      // once and never look at it again once the joint moves — either
      // leaves the tip a "disconnected socket", moving on its own with
      // nothing bound to it, and this frame comes back pixel-identical to
      // `rest`.
      expect(
        bent.pixels,
        isNot(equals(rest.pixels)),
        reason:
            'moving the tip joint did not change a single pixel of the '
            'mesh half bound to it',
      );
    });
  });

  group('the morphed shape, drawn', () {
    // `anim-19`'s own acceptance names a golden frame. `AnimatedMorphCube`
    // is the Khronos sample `morph_pipeline_test.dart` already loads through
    // the whole pipeline — decode, upload, node, weights — so this reaches
    // that same node through `ModelerStage.build`'s own `asset:` parameter
    // rather than building a scene by hand.
    test('a weighted target matches its reference frame', () async {
      final it = cpuTestDevice(width: 240, height: 160);
      // `kSamplesPath` is relative to a package under `packages/`; this app
      // lives under `apps/`, one directory further from the repo root — the
      // same reason `texture_info_upload_test.dart` spells its own sample
      // path out rather than using the constant.
      final document = await GltfLoader().load(
        File(
          '../../packages/flutter3d_samples/assets/AnimatedMorphCube.glb',
        ).readAsBytesSync(),
      );
      final asset = await ModelAsset.fromDocument(document, device: it.device);
      final stage = ModelerStage.build(device: it.device, asset: asset);

      MeshNode? morphed;
      stage.subject.traverse((SceneNode node) {
        if (node is MeshNode && node.morph != null) morphed = node;
      });
      expect(morphed, isNotNull, reason: 'the sample carries a morph target');
      morphed!.morph!.setWeights(<double>[1.0, 0.0]);
      stage.frameSubject();

      final renderer = Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      );
      final result = renderer.render(
        width: 240,
        height: 160,
        scene: stage.scene,
        views: <RenderView>[
          RenderView(
            camera: stage.camera,
            clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
          ),
        ],
      );
      final pixels = await it.device.readPixels(result.frame);
      expect(pixels, isNotNull, reason: 'the frame could not be read back');
      final frame = (
        pixels: pixels!.buffer.asUint8List(),
        width: 240,
        height: 160,
        drawCalls: result.drawCalls,
      );

      await expectMatchesGolden(frame, 'test/goldens/modeler-morphs.png');
    });
  });

  group('the simplified UV, drawn', () {
    // `pro-lod-02`'s own row: a disc, its rim faceting cut by two thirds,
    // recoloured by its own surviving UV — `r = u`, `g = v` — so a texture
    // coordinate `simplifyMeshWithAttributes` blended or dropped wrong would
    // show as a colour seam or a flat patch rather than needing a bound
    // texture to see at all.
    test('lod-uv matches its reference', () async {
      final disc = DiscShape(
        radius: 1.0,
        segments: 64,
      ).build(layout: VertexLayout.positionNormalTexcoord);
      final simplified = simplifyMeshWithAttributes(
        disc,
        targetTriangleCount: 24,
      );
      final rebuilt = simplified.withGeneratedTangents().convertedTo(
        VertexLayout.standard,
      );

      final stride = rebuilt.layout.floatsPerVertex;
      final uvOffset = rebuilt.layout.floatOffsetOf(VertexLayout.texcoord.name);
      final colorOffset = rebuilt.layout.floatOffsetOf(VertexLayout.color.name);
      for (var v = 0; v < rebuilt.vertexCount; v++) {
        final base = v * stride;
        rebuilt.vertices[base + colorOffset] =
            rebuilt.vertices[base + uvOffset];
        rebuilt.vertices[base + colorOffset + 1] =
            rebuilt.vertices[base + uvOffset + 1];
        rebuilt.vertices[base + colorOffset + 2] = 0.5;
        rebuilt.vertices[base + colorOffset + 3] = 1.0;
      }

      final frame = await renderFrame(
        width: 240,
        height: 160,
        build: (FrameRequest request) {
          final stage = ModelerStage.build(device: request.device);
          final node = stage.subject as MeshNode;
          node.mesh = DeviceMesh.upload(request.device, rebuilt);
          stage.frameSubject();
          return (scene: stage.scene, camera: stage.camera);
        },
      );

      await expectMatchesGolden(frame, 'test/goldens/lod-uv.png');
    });
  });

  group('the lathe dialog\'s own preview, drawn', () {
    // `ui-13`'s own "кадр предпросмотра = golden" — `lathe_dialog.dart`'s
    // live preview is `ModelerStage.build`'s own cube subject, replaced on
    // every edit with a mesh built from the authored `ProfileCurve`
    // exactly the way the dialog itself does it: flattened through
    // `toPolyline`, then `ParametricLathe.toEditMesh`. Built here directly
    // rather than through the dialog's own chrome, the same call this
    // package's own `mesh-lathe` fixture above already makes for a
    // pre-flattened polyline — this one instead exercises the curved half
    // of the row's own worked example, a quadratic bend into a line, the
    // one `mesh-lathe`'s own fixture (an already-flat profile) does not
    // touch.
    test(
      'a curved profile\'s flattened preview matches its reference',
      () async {
        final curve = ProfileCurve(
          points: <ProfilePoint>[
            ProfilePoint(Vector2(0, -0.6)),
            ProfilePoint(Vector2(0.5, 0.0)),
            ProfilePoint(Vector2(0.2, 0.6)),
          ],
          segments: <ProfileSegment>[
            QuadraticSegment(Vector2(0.65, -0.3)),
            const LineSegment(),
          ],
        );

        final frame = await renderFrame(
          width: 240,
          height: 160,
          build: (FrameRequest request) {
            final stage = ModelerStage.build(device: request.device);
            final node = stage.subject as MeshNode;
            node.mesh = DeviceMesh.upload(
              request.device,
              ParametricLathe(
                profile: curve.toPolyline(),
                segments: 24,
              ).toEditMesh().toMeshData(),
            );
            stage.frameSubject();
            return (scene: stage.scene, camera: stage.camera);
          },
        );

        await expectMatchesGolden(
          frame,
          'test/goldens/lathe-dialog-preview.png',
        );
      },
    );
  });

  group('the material studio\'s own preview, drawn', () {
    // `mat-15`'s own "кадр material-studio на CPU": the sphere body under the
    // Daylight preset, built the same way the dialog itself does it —
    // `ModelerStage.build`'s own cube subject swapped for a sphere and
    // painted with a material worth telling apart from clay, a floor added
    // beside it, and the scene's own environment bound to the preset's sky —
    // rather than through the dialog's chrome, the same shortcut the lathe
    // preview above already takes.
    test(
      'the sphere body under the Daylight preset matches its reference',
      () async {
        final preset = materialStudioSkyPresets()[1];

        final frame = await renderFrame(
          // `mat-31`'s own size for the three material/scene goldens this
          // app's own tests keep in `test/goldens`.
          width: 320,
          height: 200,
          settings: RenderSettings(sky: preset.sky),
          build: (FrameRequest request) {
            final stage = ModelerStage.build(device: request.device);
            (stage.subject as MeshNode)
              ..mesh = DeviceMesh.upload(
                request.device,
                const ParametricSphere().toEditMesh().toMeshData(),
              )
              ..material = Material(
                name: 'preview',
                lighting: LightingModel.pbr,
                baseColor: Vector4(0.75, 0.15, 0.12, 1.0),
                roughness: 0.25,
                metallic: 0.8,
              );
            final environment = MaterialStudioEnvironment(
              device: request.device,
              scene: stage.scene,
            )..apply(preset.sky);
            addTearDown(environment.dispose);
            stage.scene.add(
              MeshNode(
                DeviceMesh.upload(
                  request.device,
                  const ParametricPlane(
                    width: 8,
                    depth: 8,
                  ).toEditMesh().toMeshData(),
                ),
                Material(
                  name: 'floor',
                  lighting: LightingModel.pbr,
                  baseColor: Vector4(0.5, 0.5, 0.52, 1.0),
                  roughness: 0.85,
                ),
                name: 'floor',
              )..setPosition(0, -0.5, 0),
            );
            stage.frameSubject();
            return (scene: stage.scene, camera: stage.camera);
          },
        );

        await expectMatchesGolden(frame, 'test/goldens/material-studio.png');
      },
    );
  });
}
