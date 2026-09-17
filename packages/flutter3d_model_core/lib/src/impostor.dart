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
/// **The arithmetic here needs no device; the baking takes one as an
/// argument.** [ImpostorAtlas] and [ImpostorCard] are numbers a test checks
/// with nothing running, and [bakeImpostor] renders the views through
/// `pro-rn-02`'s own tiled job over a [TileDevice] the caller supplies — the
/// same shape `renderProject` already takes a device factory in, and for the
/// same reason: this package has no window and must not grow one.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart'
    show PerspectiveProjection, RenderSettings;
import 'package:flutter3d_core/formats.dart' show DecodedImage, decodePng;
import 'package:vector_math/vector_math.dart';

import 'project.dart';
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

  /// The card a bake at [distance] through [fovYRadians] actually fills.
  ///
  /// **Not the model's own bounds, and this is the mistake worth naming.** A
  /// cell holds a picture of the model taken from [distance] through a fixed
  /// field of view, so the model occupies whatever part of that frame it
  /// subtends — usually well under half of it. Drawing the whole cell onto a
  /// card the size of the model shrinks the model by exactly that fraction,
  /// which reads as an impostor that is slightly too small and pops on the
  /// swap. What the cell covers at the subject's own distance is
  /// `2 · distance · tan(fov / 2)`, and a card that size puts the picture
  /// back at the size it was taken at.
  factory ImpostorCard.framing({
    required double distance,
    double fovYRadians = math.pi / 8,
  }) {
    final double side = 2 * distance * math.tan(fovYRadians / 2);
    return ImpostorCard(width: side, height: side);
  }

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

/// A baked impostor: the atlas's own pixels, and the atlas that laid them out.
///
/// RGBA rather than a PNG, because what a caller does next is put it on a
/// texture, and the one that wants a file already has an encoder.
typedef ImpostorBake = ({ImpostorAtlas atlas, int size, Uint8List rgba});

/// [project] rendered from every one of [atlas]'s angles, composited into one
/// atlas image.
///
/// Each view is a [RenderSnapshotJob] over [tileDevice] — `pro-rn-02`'s own
/// tiled job, at one cell's resolution, from the camera
/// [ImpostorAtlas.cameraFor] gives. The background is transparent unless
/// [clearColor] says otherwise: an impostor is a silhouette on a card, and a
/// card baked against a sky carries that sky into every scene it stands in.
///
/// **One job per view rather than one grid over all of them.** The tiles of a
/// snapshot share a camera and these do not, so the eight are eight renders
/// however they are arranged — which is what keeps the composite here rather
/// than inside a job that has no idea it is filling an atlas.
///
/// **Bake from the distance the impostor will be shown at, through whatever
/// [fovYRadians] frames the subject there.** The perspective is baked into
/// the picture: a card baked from eight metres and shown from three hundred
/// carries eight metres' worth of convergence into a view that has almost
/// none, and the silhouette is visibly the wrong shape rather than merely
/// soft — measured at about fourteen percent of it in
/// `flutter3d_cpu`'s own `impostor_card_test.dart`, against three at the
/// matching distance. [distance] and [ImpostorCard.framing]'s own argument
/// are the same number for that reason.
Future<ImpostorBake> bakeImpostor({
  required ModelProject project,
  required ImpostorAtlas atlas,
  required Vector3 centre,
  required double distance,
  required TileDevice tileDevice,
  double fovYRadians = math.pi / 8,
  RenderSettings settings = const RenderSettings(),
  Vector4? clearColor,
}) async {
  final int cell = atlas.cellSize;
  final rgba = Uint8List(atlas.size * atlas.size * 4);
  for (var i = 0; i < atlas.angles; i++) {
    final Uint8List png = await RenderSnapshotJob(
      project,
      RenderPreset(
        width: cell,
        height: cell,
        camera: atlas.cameraFor(
          i,
          centre: centre,
          distance: distance,
          fovYRadians: fovYRadians,
        ),
        settings: settings,
        clearColor: clearColor ?? Vector4.zero(),
      ),
      tileDevice: tileDevice,
    ).run();
    // The bytes came straight out of the encoder this repository wrote, so a
    // null here is not a file somebody chose badly — it is the writer and the
    // reader disagreeing, which is a bug rather than a case to handle.
    final DecodedImage? view = decodePng(png);
    if (view == null) {
      throw StateError(
        'the snapshot of impostor view $i did not decode as a PNG',
      );
    }
    final ImpostorView where = atlas.viewAt(i);
    final int x0 = (where.cell.x * atlas.size).round();
    final int y0 = (where.cell.y * atlas.size).round();
    // Row by row: the cell is narrower than the atlas, so the two have
    // different strides and there is no single range to copy.
    for (var y = 0; y < cell; y++) {
      rgba.setRange(
        ((y0 + y) * atlas.size + x0) * 4,
        ((y0 + y) * atlas.size + x0 + cell) * 4,
        view.rgba,
        y * view.width * 4,
      );
    }
  }
  return (atlas: atlas, size: atlas.size, rgba: rgba);
}
