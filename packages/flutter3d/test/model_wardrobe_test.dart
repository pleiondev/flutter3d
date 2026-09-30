/// `ModelWardrobe`: models by key, put on nodes made before and after they
/// arrive, fitted, and forgotten with what wore them.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

enum _Part { jet, ship }

/// A box nine hundred units long: a free model in somebody else's unit.
ModelAsset _model(GraphicsDevice device) => ModelAsset.fromMesh(
  device,
  CuboidShape(size: Vector3(300.0, 120.0, 900.0)).build(),
);

SceneNode _wearer(Scene scene, String name) {
  final visual = SceneNode(name: name)
    ..add(
      MeshNode(
        DeviceMesh.upload(
          cpuTestDevice(width: 4, height: 4).device,
          CuboidShape(size: Vector3.all(0.5)).build(),
        ),
        Material(),
      ),
    );
  scene.add(visual);
  return visual;
}

void main() {
  late GraphicsDevice device;
  late Scene scene;

  setUp(() {
    device = cpuTestDevice(width: 4, height: 4).device;
    scene = Scene();
  });

  ModelWardrobe<_Part> wardrobe({
    void Function(ModelInstance, _Part)? onDressed,
  }) => ModelWardrobe<_Part>(
    device: device,
    scene: scene,
    looks: <_Part, ModelLook>{
      _Part.jet: const ModelLook('jet.glb', length: 2.0),
      _Part.ship: ModelLook(
        'ship.glb',
        length: 3.0,
        onGround: true,
        offset: Vector3(0.0, -0.15, 0.0),
      ),
    },
    onDressed: onDressed,
  );

  test('a node recorded before its model arrives is dressed when it does', () {
    final closet = wardrobe();
    final early = _wearer(scene, 'early');
    final primitive = early.children.single;
    closet.dress(early, _Part.jet);
    expect(early.children.single, same(primitive), reason: 'nothing yet');

    closet.put(_Part.jet, _model(device));
    expect(early.children.single, isNot(same(primitive)));
    expect(early.children.single.name, 'early model');
  });

  test('a node recorded after is dressed at once, fitted and offset', () {
    final closet = wardrobe()..put(_Part.ship, _model(device));
    final ship = _wearer(scene, 'ship');
    closet.dress(ship, _Part.ship);

    final bounds = scene.computeBounds();
    expect(bounds.max.z - bounds.min.z, closeTo(3.0, 1e-3));
    // Standing on the node, then 15 cm down.
    expect(bounds.min.y, closeTo(-0.15, 1e-3));
  });

  test('onDressed sees every instance with its part', () {
    final seen = <_Part>[];
    final closet = wardrobe(onDressed: (_, part) => seen.add(part));
    closet
      ..dress(_wearer(scene, 'a'), _Part.jet)
      ..dress(_wearer(scene, 'b'), _Part.jet)
      ..dress(_wearer(scene, 'c'), _Part.ship)
      ..put(_Part.jet, _model(device));
    expect(seen, <_Part>[_Part.jet, _Part.jet]);
  });

  test('a node forgotten is not dressed later', () {
    final closet = wardrobe();
    final gone = _wearer(scene, 'gone');
    final primitive = gone.children.single;
    closet
      ..dress(gone, _Part.jet)
      ..forget(gone)
      ..put(_Part.jet, _model(device));
    expect(gone.children.single, same(primitive));
    expect(closet.wearers, 0);
  });

  test('a file that will not load leaves the primitives and says so', () async {
    final errors = <_Part>[];
    final closet = wardrobe();
    final waiting = _wearer(scene, 'waiting');
    final primitive = waiting.children.single;
    closet.dress(waiting, _Part.jet);

    await closet.load(
      source: (path) => FileAssetSource('/nonexistent/$path'),
      onError: (part, _) => errors.add(part),
    );
    expect(errors, containsAll(<_Part>[_Part.jet, _Part.ship]));
    expect(waiting.children.single, same(primitive));
    expect(closet.has(_Part.jet), isFalse);
  });
}
