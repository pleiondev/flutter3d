/// What a runtime composes for a frame: the projection of the scene, and
/// flat or curved panels that carry Flutter widgets.
library;

import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show RigidPose;
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show TextureHandle;

import 'xr_session.dart';
import 'xr_swapchain.dart';

/// One layer of a frame, composed by the runtime in the order the frame
/// lists them.
///
/// **Open to the engine, closed to a switch.** Equirectangular and cube
/// layers are runtime features a minor may add, so this is `abstract
/// final`: only this library adds a kind, and a `switch` over layers ends
/// with a wildcard that names what it was handed.
abstract final class XrLayer {
  const XrLayer._(this.space);

  /// The space the layer's pose is in.
  final XrSpace space;
}

/// The scene, drawn once per view into the layers of [image]: what a
/// headset shows.
final class XrProjectionLayer extends XrLayer {
  /// [views] drawn into [image] from [swapchain], in [space].
  XrProjectionLayer({
    required XrSpace space,
    required this.swapchain,
    required this.image,
    required List<XrView> views,
  }) : views = List<XrView>.unmodifiable(views),
       super._(space);

  /// The images the views were drawn into.
  final XrSwapchain swapchain;

  /// This frame's image: layer `view.index` holds each view.
  final TextureHandle image;

  /// The views drawn, with the poses and angles they were drawn from (the
  /// frame's own, which a runtime reprojects against).
  final List<XrView> views;
}

/// A flat rectangle of [width] by [height] meters at [pose], showing
/// [image]: a panel of crisp text, composed by the runtime at the display's
/// own resolution rather than resampled through the scene.
final class XrQuadLayer extends XrLayer {
  /// A quad in [space].
  const XrQuadLayer({
    required XrSpace space,
    required this.pose,
    required this.width,
    required this.height,
    required this.image,
  }) : super._(space);

  /// Its center and turn; it faces along the pose's +z.
  final RigidPose pose;

  /// Metres across.
  final double width;

  /// Metres up.
  final double height;

  /// What it shows.
  final TextureHandle image;
}

/// A band of a cylinder around [pose], of [radius] meters, [centralAngle]
/// radians wide and [height] meters tall, showing [image] on its inside: a
/// wide panel that stays the same distance from the eyes.
final class XrCylinderLayer extends XrLayer {
  /// A cylinder band in [space].
  const XrCylinderLayer({
    required XrSpace space,
    required this.pose,
    required this.radius,
    required this.centralAngle,
    required this.height,
    required this.image,
  }) : super._(space);

  /// The cylinder's center and turn; the band is centered on the pose's −z.
  final RigidPose pose;

  /// Metres from the axis.
  final double radius;

  /// How much of the circle it covers, radians.
  final double centralAngle;

  /// Metres tall.
  final double height;

  /// What it shows.
  final TextureHandle image;
}

/// The shape a panel is shown in.
///
/// **Open.** A quad and a cylinder are what both runtimes compose; a
/// sphere's inside or a cube is a shape a minor may add.
final class XrPanelShape {
  const XrPanelShape._(this.name);

  /// Flat: an [XrQuadLayer].
  static const XrPanelShape quad = XrPanelShape._('quad');

  /// Curved around the viewer: an [XrCylinderLayer].
  static const XrPanelShape cylinder = XrPanelShape._('cylinder');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<XrPanelShape> values = <XrPanelShape>[quad, cylinder];

  /// The value called [name], or null for a name this version does not
  /// know.
  static XrPanelShape? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'XrPanelShape.$name';
}

/// A Flutter widget shown in a headset as a layer of its own: a menu, a
/// readout, a page of a lesson.
///
/// **Crisp because it is not drawn into the scene.** [child] is drawn into
/// a texture of [pixelWidth] × [pixelHeight] (`WidgetTexture`), and the
/// runtime composes that texture as an [XrQuadLayer] or an
/// [XrCylinderLayer], sampling it once at the display's resolution; text
/// drawn into the scene and then through a lens is sampled twice and
/// blurs. The widget is drawn again when [invalidate] is called, not every
/// frame.
final class XrPanel {
  /// [child] shown [width] meters wide at [pose] in the session's space.
  XrPanel({
    required this.child,
    required this.pose,
    this.width = 1.0,
    this.height = 0.6,
    this.pixelWidth = 1024,
    this.pixelHeight = 614,
    this.shape = XrPanelShape.quad,
    this.radius = 1.5,
  });

  /// What it shows.
  final Widget child;

  /// Where it is: a quad's center, a cylinder's axis.
  RigidPose pose;

  /// Metres across: a quad's width, a cylinder's arc length.
  final double width;

  /// Metres up.
  final double height;

  /// The texture's pixels across.
  final int pixelWidth;

  /// The texture's pixels down.
  final int pixelHeight;

  /// Flat or curved.
  final XrPanelShape shape;

  /// A cylinder's radius, in meters; a quad has none.
  final double radius;

  int _generation = 0;

  /// How many times [invalidate] has been called: the driver draws the
  /// widget again when this moves.
  int get generation => _generation;

  /// Asks for [child] to be drawn again before the next frame.
  void invalidate() => _generation++;

  /// The layer this panel is, showing [image], in [space].
  XrLayer layer(XrSpace space, TextureHandle image) => switch (shape) {
    XrPanelShape.cylinder => XrCylinderLayer(
      space: space,
      pose: pose,
      radius: radius,
      centralAngle: width / radius,
      height: height,
      image: image,
    ),
    XrPanelShape.quad => XrQuadLayer(
      space: space,
      pose: pose,
      width: width,
      height: height,
      image: image,
    ),
    _ => throw UnsupportedError('no layer is made for a $shape panel yet'),
  };
}
