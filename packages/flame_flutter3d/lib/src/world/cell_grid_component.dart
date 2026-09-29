import 'package:flame/components.dart' show Vector2;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:vector_math/vector_math.dart' show Vector4;

import '../host/has_flutter3d.dart';
import '../transform/object3d_component.dart';
import '../transform/plane.dart';

/// A [CellGrid] as a bridged component: drawn as blocks, worn away by
/// [hitAt]. A Space Invaders shield.
///
/// The grid's corner is at this component's position, cell (0, 0) at the
/// top left as Flame sees it, one [CellGrid.cell] a cell; [size] is the
/// grid's, so a `RectangleHitbox()` covers it and Flame reports a shot
/// reaching it, and [hitAt] says whether the shot met a block there.
///
/// **Drawn again after every hit, from what is left.** The old mesh goes
/// back through the renderer after the frames in flight, as any mesh a
/// game lets go of should; a grid with nothing left hides its node.
class CellGridComponent extends Object3dComponent {
  CellGridComponent({
    required this.grid,
    required this.device,
    required super.scene,
    required super.plane,
    required this.material,
    this.depth,
    this.colour,
    super.position,
    super.elevation,
  }) : super(
         node: SceneNode(name: 'cell grid'),
         direction: SyncDirection.flameToScene,
         size: Vector2(grid.columns * grid.cell, grid.rows * grid.cell),
       ) {
    _rebuild();
  }

  final CellGrid grid;
  final GraphicsDevice device;
  final engine.Material material;

  /// How deep the blocks stand; a cell's size unless given.
  final double? depth;

  /// A colour the blocks are painted, if any.
  final Vector4? colour;

  MeshNode? _blocks;

  /// Takes away the cells within [radius] metres of [at], a point in the
  /// game's own coordinates, and draws what is left. True when a cell was
  /// there to take: the shot hit the shield rather than passing through a
  /// hole in it.
  bool hitAt(Vector2 at, {double radius = 0.6}) {
    final local = absoluteToLocal(at);
    final gone = grid.clearAround(local.x, local.y, radius);
    if (gone == 0) return false;
    _rebuild();
    return true;
  }

  void _rebuild() {
    final flat = BridgePlane(
      axis: plane.axis,
      constant: 0.0,
      flipY: plane.flipY,
    );
    final data = grid.mesh(
      place: (x, y) => flat.to3d(Vector2(x, y)),
      depth: depth,
      colour: colour,
    );
    final old = _blocks;
    if (data == null) {
      old?.visible = false;
    } else {
      final blocks = MeshNode(DeviceMesh.upload(device, data), material);
      node.add(blocks);
      _blocks = blocks;
    }
    if (old != null && data != null) {
      old.removeFromParent();
      _letGo(old.mesh as DeviceMesh);
    }
  }

  void _letGo(DeviceMesh mesh) {
    final game = findGame();
    final drawing = game is HasFlutter3d ? game.renderer : null;
    if (drawing != null) {
      drawing.releaseMeshAfterFrame(mesh);
    } else {
      device
        ..releaseGeometry(mesh.vertices)
        ..releaseGeometry(mesh.indices);
    }
  }
}
