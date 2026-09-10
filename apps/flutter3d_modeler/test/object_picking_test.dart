/// A click answers with an object, and a click on the gizmo answers with
/// nothing at all.
///
///     flutter test test/object_picking_test.dart
///
/// The two acceptance cases of `view-08` are drawn rather than asserted from a
/// node handed over by hand: the pick that matters is the one that comes back
/// out of the renderer's id pass, and a test that fed `objectUnder` a node it
/// had chosen itself would pass on a frame where the cube was never drawn.
/// `staging.dart` builds the world, because `no test builds its own world` in
/// `tool/structure.dart` says so.
///
/// The one thing standing in for something that does not exist yet is the
/// gizmo. Its arrows arrive with `view-12`; until then the second case puts a
/// small mesh between the camera and the cube and tags it the way the gizmo
/// will be tagged, which is the whole of what the exclusion rule sees. When
/// view-12 lands, this stops building it and asks the stage for it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/object_picking.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 160;
const int _height = 100;

/// The stage, framed, with a renderer over it.
({GraphicsDevice device, Renderer renderer, ModelerStage stage}) _viewport() {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
  final stage = ModelerStage.build(device: it.device)..frameSubject();
  return (device: it.device, renderer: renderer, stage: stage);
}

/// Asks for the mesh under the middle of the viewport and draws the frame that
/// answers it.
Future<SceneNode?> _pickCentre(Renderer renderer, ModelerStage stage) {
  final pick = renderer.pickPixel(0.5, 0.5);
  renderer.render(
    width: _width,
    height: _height,
    scene: stage.scene,
    views: stage.views(),
  );
  return pick;
}

void main() {
  test('a click in the cube is the cube', () async {
    final it = _viewport();

    final node = await _pickCentre(it.renderer, it.stage);
    expect(node, isNotNull, reason: 'nothing was drawn in the middle');

    // Mutation: have `objectUnder` answer `pickedNothing` for a node that is
    // not tagged — the click that should pick up an object instead clears the
    // selection, which is a modeller in which nothing can ever be selected.
    final pick = objectUnder(node);
    expect(pick, isA<PickedObject>());
    expect((pick as PickedObject).node, same(it.stage.subject));

    // Mutation: make a plain click add rather than replace — every click grows
    // the selection and the only way back to one object is a click on empty
    // space, which a viewport full of objects does not have.
    final selection = applyPick(
      <PickedObject>{PickedObject(SceneNode(name: 'something else'))},
      pick,
      extend: false,
    );
    expect(selection, <PickedObject>{pick});
  });

  test('a click on the gizmo is not the object under the gizmo', () async {
    final it = _viewport();

    // The arrow, where view-12 will put it: between the camera and the object
    // it moves, small enough to be a handle and big enough to cover the pixel
    // in the middle. Tagged on the holder rather than on the mesh, because the
    // gizmo is a holder with three arrows under it.
    final gizmo = SceneNode(name: 'gizmo');
    markService(gizmo);
    final eye = it.stage.camera.readWorldPosition();
    final centre = it.stage.subjectBounds()!.center;
    gizmo.add(
      MeshNode(
          DeviceMesh.upload(it.device, EditMesh.cuboid().toMeshData()),
          Material(name: 'arrow', lighting: LightingModel.unlit),
          name: 'arrow-x',
        )
        ..setPositionFrom(eye + (centre - eye) * 0.15)
        ..setUniformScale(0.06),
    );
    it.stage.scene.add(gizmo);

    final node = await _pickCentre(it.renderer, it.stage);
    expect(node, isNotNull, reason: 'the arrow was not drawn');
    expect(
      node,
      isNot(same(it.stage.subject)),
      reason: 'the arrow is in front',
    );

    // Mutation: look at the picked node's own `layerMask` instead of walking
    // its parents — the arrow is a child of the tagged holder, so it comes
    // back as an object and a click on the gizmo selects the arrow itself.
    final pick = objectUnder(node);
    expect(pick, isA<PickedService>());

    // The object is not what the click answers either. Every drag of the gizmo
    // starts with this click, so the selection it did not describe survives it
    // whole. Mutation: fold `PickedService` into the background case of
    // `applyPick` — grabbing the gizmo empties the selection and the drag that
    // was starting has nothing left to move.
    final held = <PickedObject>{PickedObject(it.stage.subject)};
    expect(applyPick(held, pick, extend: false), held);
    expect(applyPick(held, pick, extend: true), held);
  });

  test('shift amends the selection and a bare click on nothing empties it', () {
    final first = PickedObject(SceneNode(name: 'first'));
    final second = PickedObject(SceneNode(name: 'second'));
    final both = <PickedObject>{first, second};

    // Mutation: drop the `extend` guard from the object case so shift replaces
    // like a bare click — a person picking a second object loses the first,
    // and nothing can ever be moved as a pair.
    expect(applyPick(<PickedObject>{first}, second, extend: true), both);

    // Mutation: make a shift-click on a selected object add instead of remove
    // — since adding it twice does nothing, the gesture becomes a no-op and
    // dropping one object out of thirty means picking the other twenty-nine
    // again.
    expect(applyPick(both, first, extend: true), <PickedObject>{second});

    // Mutation: clear on a shift-click on the background — a slip onto empty
    // space in the middle of composing a selection throws the composition
    // away.
    expect(applyPick(both, pickedNothing, extend: true), both);

    // Mutation: keep the selection on a bare click on the background — there
    // is then no gesture at all for "select nothing".
    expect(applyPick(both, pickedNothing, extend: false), isEmpty);

    // The result is not the caller's set, and mutating what was passed in does
    // not reach it. Mutation: return `selection` itself from the unchanged
    // cases — the cubit's next `add` to its own set silently edits the value
    // it already published.
    final live = <PickedObject>{first};
    final taken = applyPick(live, pickedNothing, extend: true);
    live.add(second);
    expect(taken, <PickedObject>{first});
    expect(() => taken.add(second), throwsUnsupportedError);
  });

  test('one object drawn as two nodes is selected once', () {
    // What glTF does at every material boundary: one object of the document,
    // two meshes in the scene. Mutation: compare nodes rather than ids in
    // `PickedObject.==` — shift-clicking the second half of a two-material
    // object adds it a second time, and it is then highlighted twice and
    // offered two transform gizmos.
    final metal = SceneNode(name: 'lamp.metal');
    final glass = SceneNode(name: 'lamp.glass');
    Object? identify(SceneNode node) => node.name!.split('.').first;

    final first = objectUnder(metal, identify: identify);
    final second = objectUnder(glass, identify: identify);
    expect(first, second);
    expect((second as PickedObject).node, same(glass));

    final selection = applyPick(
      <PickedObject>{first as PickedObject},
      second,
      extend: true,
    );
    // Shift on something already selected removes it, and the second node is
    // the same object, so the object goes.
    expect(selection, isEmpty);

    // A node the document does not claim is furniture, not an object.
    // Mutation: fall back to the node when `identify` returns null — a grid
    // line nobody registered becomes selectable, and it is selectable under
    // the name of a node rather than of anything a person can edit.
    expect(
      objectUnder(SceneNode(name: 'grid'), identify: (SceneNode _) => null),
      isA<PickedService>(),
    );
  });
}
