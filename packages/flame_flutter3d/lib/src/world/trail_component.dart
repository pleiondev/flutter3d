import 'package:flame/components.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;

import '../host/has_flutter3d.dart';
import '../transform/object3d_component.dart';

/// A line drawn behind the bridged component it is added to: a missile's
/// smoke, a comet's tail. Missile Command.
///
/// A point is laid every [spacing] metres the component moves, up to
/// [length] points, the oldest let go as new ones come; the line is a
/// `LineStripNode` in the `HasFlutter3d` game's scene, [width] pixels
/// across, and goes, its mesh with it, when this component does.
class TrailComponent extends Component {
  TrailComponent({
    this.spacing = 0.5,
    this.length = 48,
    this.width = 3.0,
    Vector4? colour,
  }) : colour = colour ?? Vector4.all(1.0);

  final double spacing;
  final int length;
  final double width;
  final Vector4 colour;

  LineStripNode? _line;
  HasFlutter3d? _host;

  /// The line, while this is in a game with a 3D world.
  LineStripNode? get line => _line;

  @override
  void onMount() {
    super.onMount();
    final game = findGame();
    if (game is! HasFlutter3d || !game.has3d) return;
    _host = game;
    final line = LineStripNode(
      device: game.device,
      material: engine.Material.polyline(
        viewportWidth: game.size.x,
        viewportHeight: game.size.y,
      ),
      capacity: length,
      width: width,
      colour: colour,
      name: 'trail',
    );
    game.scene.add(line);
    _line = line;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final line = _line;
    final owner = parent;
    if (line == null || owner is! Object3dComponent) return;
    final at = owner.scenePosition;
    final points = line.points;
    if (points.isEmpty || points.last.distanceTo(at) >= spacing) {
      line.append(at);
    }
  }

  @override
  void onRemove() {
    final line = _line;
    final host = _host;
    _line = null;
    if (line != null) {
      line.removeFromParent();
      final mesh = line.mesh as DeviceMesh;
      final drawing = host?.renderer;
      if (drawing != null) {
        drawing.releaseMeshAfterFrame(mesh);
      } else {
        host?.device
          ?..releaseGeometry(mesh.vertices)
          ..releaseGeometry(mesh.indices);
      }
    }
    super.onRemove();
  }
}
