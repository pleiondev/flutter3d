/// `pro-lod-05n`: an impostor — several angles of a model baked into one
/// atlas, and the card that shows them.
///
/// **A tree at three hundred metres is two triangles with a picture on it,
/// not five thousand triangles.** That is the whole of why this exists: past
/// the distance where a silhouette is a few dozen pixels, nothing about the
/// geometry survives the rasterizer, and paying for it is paying for
/// nothing.
///
/// **Angles round the equator, not a sphere of them.** A tree, a rock and a
/// building are looked at from roughly eye level; the half of a spherical
/// atlas spent on views from underneath is half the texture spent on
/// something nobody sees. Eight is the usual number and the default here:
/// forty-five degrees between neighbours, which is close enough that the
/// pop between two of them is under the pixel budget at the distance an
/// impostor is used at.
///
/// **The card faces the camera about the up axis only.** A billboard that
/// also tilted toward a camera looking down would swing its own baked
/// horizon into view, and the impostor's whole trick is that the picture was
/// taken from eye level.
///
/// **This file picks the angle and lays out the atlas; it draws nothing.**
/// Rendering the eight views is `pro-rn-02`'s own tiled job, over the same
/// `SnapshotCamera` a snapshot uses, and the card is a two-triangle mesh a
/// caller builds — both of those need a device, and everything here is
/// arithmetic a test can check without one.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart' show PerspectiveProjection;
import 'package:vector_math/vector_math.dart';

import 'render_snapshot.dart';

/// Where one baked view sits in the atlas, and which way it was taken from.
typedef ImpostorView = ({int index, double yaw, AtlasCell cell});

/// A rectangle of the atlas, in `0..1`.
///
/// **Named for the atlas rather than `Rect`**, which every Flutter file that
/// imports this package already has from `dart:ui` — a second one exported
/// into the same scope is a name collision in somebody else's file, which is
/// exactly what it was before this comment.
typedef AtlasCell = ({double x, double y, double width, double height});

/// The angles an impostor holds and where each of them lives in its atlas.
final class ImpostorAtlas {
  ImpostorAtlas({this.angles = 8, this.size = 1024})
    : assert(angles > 0, 'an impostor of no angles is a blank card'),
      columns = _columnsFor(angles);

  /// How many views round the equator. Eight by default — see the library
  /// comment for why that number and why round rather than over.
  final int angles;

  /// The atlas's own side, in texels.
  final int size;

  /// How many cells across. A square-ish grid, so a cell is as close to
  /// square as the count allows: eight views in four columns of two beats
  /// eight in a row, where each cell would be a letterbox a silhouette does
  /// not fill.
  final int columns;

  int get rows => (angles / columns).ceil();

  /// The side of one cell, in texels.
  int get cellSize => size ~/ math.max(columns, rows);

  /// Every view, in order.
  List<ImpostorView> get views => <ImpostorView>[
    for (var i = 0; i < angles; i++) viewAt(i),
  ];

  /// View [index] — its own yaw and the cell it occupies.
  ImpostorView viewAt(int index) {
    final int column = index % columns;
    final int row = index ~/ columns;
    final double width = 1 / columns;
    final double height = 1 / rows;
    return (
      index: index,
      yaw: index * 2 * math.pi / angles,
      cell: (x: column * width, y: row * height, width: width, height: height),
    );
  }

  /// Which view a camera at [cameraYaw] should be shown, and how far between
  /// it and the next one the camera has turned.
  ///
  /// **The nearer of the two, and the blend beside it.** Snapping to the
  /// nearest is what a cheap impostor does and is where the pop comes from;
  /// handing back how far between them the camera stands lets a shader cross-
  /// fade, which is what turns eight pictures into something that reads as
  /// turning rather than as flicking.
  ({int view, int next, double blend}) pick(double cameraYaw) {
    final double step = 2 * math.pi / angles;
    final double turns = (cameraYaw % (2 * math.pi)) / step;
    final int view = turns.floor() % angles;
    return (
      view: view,
      next: (view + 1) % angles,
      blend: turns - turns.floor(),
    );
  }

  /// The camera that takes view [index], looking at [centre] from [distance].
  ///
  /// **Level with the model, always.** The pitch an impostor is baked at is
  /// the pitch it is honest at; baking from above and showing at eye level
  /// is the one mistake that makes an impostor look like a sticker.
  SnapshotCamera cameraFor(
    int index, {
    required Vector3 centre,
    required double distance,
    double fovYRadians = math.pi / 8,
  }) {
    final double yaw = viewAt(index).yaw;
    return SnapshotCamera(
      position: centre + Vector3(math.sin(yaw), 0, math.cos(yaw)) * distance,
      target: centre,
      projection: PerspectiveProjection(
        fovYRadians: fovYRadians,
        near: math.max(distance * 0.01, 1e-6),
        far: distance * 10 + 10,
      ),
    );
  }

  /// A square grid that is as square as [angles] allows.
  static int _columnsFor(int angles) {
    final int side = math.sqrt(angles).ceil();
    return math.max(side, 1);
  }

  @override
  String toString() =>
      'ImpostorAtlas($angles angles, $columns by $rows cells of $cellSize)';
}

/// The two triangles an impostor is drawn on, in the plane facing the
/// camera about the up axis.
///
/// [width] and [height] are the card's own size in metres — a caller takes
/// them from the model's own bounds, so the card covers the silhouette it
/// replaced.
final class ImpostorCard {
  const ImpostorCard({required this.width, required this.height});

  final double width;
  final double height;

  /// The four corners, bottom-left first, turned to face a camera at
  /// [cameraYaw] and standing at [centre].
  ///
  /// **About the up axis only.** A card that also tilted toward a camera
  /// looking down would swing its own baked horizon into view, and the trick
  /// only works while the picture and the view agree about where level is.
  List<Vector3> cornersAt(Vector3 centre, double cameraYaw) {
    final Vector3 right = Vector3(math.cos(cameraYaw), 0, -math.sin(cameraYaw))
      ..scale(width / 2);
    final Vector3 up = Vector3(0, height / 2, 0);
    return <Vector3>[
      centre - right - up,
      centre + right - up,
      centre + right + up,
      centre - right + up,
    ];
  }
}
