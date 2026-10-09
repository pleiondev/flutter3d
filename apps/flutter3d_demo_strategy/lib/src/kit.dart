/// What the match is dressed in: workers, soldiers and siege rams in each
/// side's colours, castles for halls, rock and gold for seams, woods, water,
/// and a painted hillside under all of it.
///
/// **Composed here, in code, from a kit of parts.** A hall is a dozen
/// pieces of Kenney's Castle Kit — four corner towers, a keep, the walls
/// between, banners — joined into one mesh, so the picking pass still sees
/// one hall and the renderer still draws one node. Writing the layout down
/// as code rather than baking it into a file keeps it something a reader can
/// see and change: a hall is the list in [_castle], not a binary.
///
/// **Team colour is a repaint of the palette, not a second model.** The
/// Kenney kits share a palette texture whose blue swatches are the accent —
/// roofs, banners, the ram's canopy — so the far side's castle is the same
/// mesh drawn with a copy of the palette whose blues are turned red. The
/// soldier's plume runs the other way, red turned blue for the near side.
/// The workers come from two different characters of one pack, one in a
/// blue shirt and one in a red.
///
/// **Nothing here touches the match.** The match is opened before any of
/// this runs and none of it is consulted by a step; a failed load is a game
/// drawn in the plain boxes `StrategyVisuals` falls back to, not a game that
/// does not start.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_demo_content/map_world.dart' show nearestSeam;
import 'package:flutter3d_game_strategy/bridge.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:vector_math/vector_math.dart';

import 'ground_paint.dart';
import 'woods.dart';

/// How high the ponds stand, in metres.
///
/// What the core's pond in `map_world.dart` is filled to, and the painted
/// sheet stands at before it: the simulation's ground is the pond's floor,
/// and a unit that walks into it wades. Low enough here that only the
/// deepest hollow of `map_a` holds any, and none of the paths a crowd takes
/// runs through it.
const double pondLevel = 0.3;

/// Everything the match is drawn in, loaded once.
final class StrategyKit {
  const StrategyKit._({
    required this.looks,
    required this.hall,
    required this.hallSize,
    required this.hallSides,
    required this.seam,
    required this.woods,
    required this.ground,
  });

  /// Workers, soldiers and rams, side by side.
  final List<UnitLook> looks;

  /// The castle every hall is drawn as, grounded at its local origin.
  final DeviceMesh hall;

  /// [hall]'s own width, height and depth.
  final Vector3 hallSize;

  /// The castle's material for each side.
  final List<RenderMaterial> hallSides;

  /// What a seam looks like.
  final MeshLook seam;

  /// The trees, one batch per kind.
  final List<PropBatch> woods;

  /// The painted hillside.
  final RenderMaterial ground;

  /// Loads and composes the whole kit for [simulation]'s map, or null if
  /// any of it fails to load.
  static Future<StrategyKit?> load(
    GraphicsDevice device,
    StrategySimulation simulation,
  ) async {
    try {
      return await _Loader(device).load(simulation);
    } catch (error, stack) {
      debugPrint('strategy: the kit did not load ($error)\n$stack');
      return null;
    }
  }
}

/// Where the shipped files are.
const String _models = 'assets/models';
const String _textures = 'assets/textures';

/// The nature kit's colours, by its own material names, replaced.
///
/// The kit is drawn in a pale teal-and-salmon palette that suits it on a
/// grey backdrop and looks like frost on painted grass; these are the same
/// parts in the greens and browns of the ground they stand on.
final Map<String?, Vector4> _natureColours = <String?, Vector4>{
  'leafsGreen': Vector4(0.18, 0.37, 0.11, 1.0),
  'leafsDark': Vector4(0.10, 0.29, 0.13, 1.0),
  'woodBark': Vector4(0.42, 0.27, 0.15, 1.0),
  'woodBarkDark': Vector4(0.31, 0.20, 0.12, 1.0),
  // Darker than it looks written down: under the map's sun a mid grey comes
  // out nearly white, and a seam should read as rock, not chalk.
  'stone': Vector4(0.11, 0.105, 0.1, 1.0),
  '_defaultMat': Vector4(0.11, 0.105, 0.1, 1.0),
};

/// How tall a worker is drawn, in metres.
const double _workerHeight = 1.5;

/// Hues, in degrees, of the palette's two accent swatches.
const double _blue = 216.0;
const double _red = 1.6;

final class _Loader {
  _Loader(this.device);

  final GraphicsDevice device;
  final Map<String, Future<List<MeshData>>> _pieces =
      <String, Future<List<MeshData>>>{};

  Future<StrategyKit> load(StrategySimulation simulation) async {
    final Rgba8Image castlePalette = await _image('castle-colormap.png');
    final Rgba8Image arenaPalette = await _image('arena-colormap.png');
    final RenderMaterial castleBlue = _textured(castlePalette);
    final RenderMaterial castleRed = _textured(
      _repaint(castlePalette, from: _blue, to: _red),
    );
    final RenderMaterial arenaRed = _textured(arenaPalette);
    final RenderMaterial arenaBlue = _textured(
      _repaint(arenaPalette, from: _red, to: _blue),
    );
    final RenderMaterial plain = RenderMaterial(
      lighting: LightingModel.pbr,
      roughness: 0.85,
    );

    final MeshData hall = await _castle();
    final Aabb3 hallBounds = hall.computeBounds();

    // A head taller than life: from where the map camera hangs a 1.2 m
    // worker is a dot, and 1.5 m is still inside the 0.8 m a worker claims
    // across, so neighbours do not walk through each other on screen.
    final DeviceMesh worker0 = _upload(
      await _standing(await _whole('blocky-p.glb'), height: _workerHeight),
    );
    final DeviceMesh worker1 = _upload(
      await _standing(await _whole('blocky-k.glb'), height: _workerHeight),
    );
    final DeviceMesh soldier = _upload(await _soldier());
    final DeviceMesh ram = _upload(await _ram());

    final List<MeshLook> workers = <MeshLook>[
      MeshLook(worker0, _textured(await _image('blocky-p.png'))),
      MeshLook(worker1, _textured(await _image('blocky-k.png'))),
    ];

    return StrategyKit._(
      looks: <UnitLook>[
        UnitLook(kind: UnitType.worker.name, sides: workers),
        UnitLook(
          kind: UnitType.soldier.name,
          sides: <MeshLook>[
            MeshLook(soldier, arenaBlue),
            MeshLook(soldier, arenaRed),
          ],
        ),
        UnitLook(
          kind: UnitType.tank.name,
          sides: <MeshLook>[
            MeshLook(ram, castleBlue),
            MeshLook(ram, castleRed),
          ],
        ),
      ],
      hall: _upload(hall),
      hallSize: hallBounds.max - hallBounds.min,
      hallSides: <RenderMaterial>[castleBlue, castleRed],
      seam: MeshLook(_upload(await _seam()), plain),
      woods: await _woods(simulation, plain),
      ground: await _ground(simulation),
    );
  }

  // ------------------------------------------------------------------ pieces

  /// Every surface of [file], in the engine's standard layout, placed by its
  /// own node transforms and coloured by its own material's base colour —
  /// which is white for the textured kits and the whole colour for the
  /// nature kit, whose models carry no texture at all.
  Future<List<MeshData>> _piece(String file) =>
      _pieces.putIfAbsent(file, () async {
        final ModelDocument document = await decodeModelInIsolate(
          ModelLoadRequest(source: BundleAssetSource('$_models/$file')),
        );
        return <MeshData>[
          for (final ModelSurface surface in document.surfaces)
            _coloured(
              surface.mesh
                  .convertedTo(VertexLayout.standard)
                  .transformed(surface.transform),
              switch (surface.materialIndex) {
                final int i =>
                  _natureColours[document.materials[i].name] ??
                      _srgbVector(document.materials[i].baseColor),
                null => Vector4(1.0, 1.0, 1.0, 1.0),
              },
            ),
        ];
      });

  /// [file]'s surfaces joined into one mesh.
  Future<MeshData> _whole(String file) async =>
      MeshData.merge(await _piece(file));

  /// [file] placed by [at], with every vertex coloured [tint] if given.
  Future<List<MeshData>> _placed(
    String file,
    Matrix4 at, {
    Vector4? tint,
  }) async => <MeshData>[
    for (final MeshData part in await _piece(file))
      tint == null
          ? part.transformed(at)
          : _coloured(part.transformed(at), tint),
  ];

  /// [mesh] moved so it stands on Y = 0, centred on X and Z, and scaled so
  /// it is [height] tall.
  Future<MeshData> _standing(MeshData mesh, {required double height}) async =>
      mesh.transformed(_grounding(mesh.computeBounds(), height));

  static Matrix4 _grounding(Aabb3 bounds, double height) {
    final double scale = height / (bounds.max.y - bounds.min.y);
    return Matrix4.diagonal3Values(scale, scale, scale)..translateByDouble(
      -(bounds.min.x + bounds.max.x) / 2.0,
      -bounds.min.y,
      -(bounds.min.z + bounds.max.z) / 2.0,
      1.0,
    );
  }

  /// A piece's placement: moved to `(x, y, z)`, turned [yaw] degrees about
  /// +Y, and scaled.
  static Matrix4 _at(
    double x,
    double y,
    double z, {
    double yaw = 0.0,
    double scale = 1.0,
  }) => Matrix4.translationValues(x, y, z)
    ..rotateY(yaw * math.pi / 180.0)
    ..scaleByDouble(scale, scale, scale, 1.0);

  // ------------------------------------------------------------------ halls

  /// The castle a hall is drawn as, in Castle Kit metres — six across and
  /// five deep, which the hall's own twelve by ten stretches by two.
  ///
  /// Walls round a yard, a hexagonal tower at each corner, and a square keep
  /// at the back with the tallest roof on the map, so a hall reads as the
  /// thing to defend from as far away as the camera goes. The banners on the
  /// front wall and the flags on the roofs are the palette's blue — the part
  /// the far side's copy turns red.
  Future<MeshData> _castle() async {
    final parts = <MeshData>[];
    Future<void> put(String piece, Matrix4 at) async =>
        parts.addAll(await _placed('castle-$piece.glb', at));

    const double halfX = 2.5;
    const double halfZ = 2.0;
    // The curtain wall: one block a metre, along each side, between the
    // corners.
    for (var x = -halfX + 1.0; x <= halfX - 1.0 + 1e-6; x += 1.0) {
      await put('wall', _at(x, 0.0, halfZ));
      await put('wall', _at(x, 0.0, -halfZ, yaw: 180.0));
    }
    for (var z = -halfZ + 1.0; z <= halfZ - 1.0 + 1e-6; z += 1.0) {
      await put('wall', _at(halfX, 0.0, z, yaw: 90.0));
      await put('wall', _at(-halfX, 0.0, z, yaw: -90.0));
    }
    // A corner tower: a hexagonal drum rising past the wall, a parapet, and
    // a roof.
    for (final (double x, double z) in <(double, double)>[
      (-halfX, -halfZ),
      (halfX, -halfZ),
      (-halfX, halfZ),
      (halfX, halfZ),
    ]) {
      await put('tower-hexagon-base', _at(x, 0.0, z, scale: 1.25));
      await put('tower-hexagon-mid', _at(x, 1.31 * 1.25, z, scale: 1.25));
      await put(
        'tower-hexagon-roof',
        _at(x, (1.31 + 0.46) * 1.25, z, scale: 1.25),
      );
    }
    // The keep: a square tower twice a corner's width, at the back of the
    // yard, with a flag on top.
    const double keep = 2.0;
    const double keepZ = -0.6;
    await put('tower-square-base', _at(0.0, 0.0, keepZ, scale: keep));
    await put(
      'tower-square-mid-windows',
      _at(0.0, 1.01 * keep, keepZ, scale: keep),
    );
    await put(
      'tower-square-top-roof-high',
      _at(0.0, 2.02 * keep, keepZ, scale: keep),
    );
    await put(
      'flag',
      _at(0.0, (2.02 + 1.35) * keep - 0.15, keepZ, scale: 1.4, yaw: 90.0),
    );
    // Banners hung on the front wall either side of the middle.
    for (final double x in <double>[-1.0, 1.0]) {
      await put('flag-banner-long', _at(x, 0.15, halfZ + 0.52, yaw: -90.0));
    }
    return MeshData.merge(parts);
  }

  // ------------------------------------------------------------------ units

  /// Mini Arena's soldier, 1.65 m to the top of the plume — overgrown by
  /// the same head as the workers — with its spear held upright in the right
  /// hand so a squad reads as armed from above.
  Future<MeshData> _soldier() async {
    final MeshData body = await _whole('arena-soldier.glb');
    final Matrix4 ground = _grounding(body.computeBounds(), 1.65);
    final List<MeshData> spear = await _placed(
      'arena-spear.glb',
      ground * _at(-0.155, 0.08, 0.05, scale: 1.45),
    );
    return MeshData.merge(<MeshData>[body.transformed(ground), ...spear]);
  }

  /// Castle Kit's siege ram, turned so the ram points the way it drives,
  /// about two and a half metres long.
  Future<MeshData> _ram() async {
    final MeshData ram = await _whole('castle-siege-ram.glb');
    final MeshData turned = ram.transformed(_at(0.0, 0.0, 0.0, yaw: -90.0));
    return _standing(turned, height: 1.45);
  }

  // ------------------------------------------------------------------ seams

  /// A seam: an outcrop of grey stone with gold showing through it, about
  /// five metres across. The gold is the nature kit's small stones coloured
  /// by hand — the kit has rock and no ore.
  Future<MeshData> _seam() async {
    final Vector4 gold = Vector4(1.0, 0.72, 0.18, 1.0);
    final parts = <MeshData>[
      ...await _placed(
        'nature-stone_tallA.glb',
        _at(0.0, -0.1, 0.0, scale: 3.2),
      ),
      ...await _placed(
        'nature-stone_tallA.glb',
        _at(1.4, -0.1, 0.9, yaw: 120.0, scale: 2.2),
      ),
      ...await _placed(
        'nature-stone_largeA.glb',
        _at(-1.6, -0.1, 0.6, yaw: 40.0, scale: 3.0),
      ),
      ...await _placed(
        'nature-stone_largeA.glb',
        _at(0.6, -0.1, -1.7, yaw: 200.0, scale: 2.6),
      ),
    ];
    final math.Random scatter = math.Random(7);
    for (var i = 0; i < 9; i++) {
      final double angle = i / 9.0 * math.pi * 2.0;
      final double r = 1.6 + scatter.nextDouble() * 1.2;
      parts.addAll(
        await _placed(
          'nature-stone_smallA.glb',
          _at(
            math.cos(angle) * r,
            -0.05,
            math.sin(angle) * r,
            yaw: scatter.nextDouble() * 360.0,
            scale: 1.6 + scatter.nextDouble() * 1.4,
          ),
          tint: gold,
        ),
      );
    }
    return MeshData.merge(parts);
  }

  // ------------------------------------------------------------------ woods

  Future<List<PropBatch>> _woods(
    StrategySimulation simulation,
    RenderMaterial plain,
  ) async {
    // In the order of `woodScales`, whose scales they are drawn at.
    const List<String> kinds = <String>[
      'nature-tree_pineTallA_detailed.glb',
      'nature-tree_pineRoundC.glb',
      'nature-tree_oak.glb',
      'nature-tree_default.glb',
      'nature-tree_detailed.glb',
    ];
    final List<List<Matrix4>> placed = plantWoods(
      simulation: simulation,
      kinds: woodScales,
      waterLevel: pondLevel,
    );
    return <PropBatch>[
      for (var i = 0; i < kinds.length; i++)
        PropBatch(
          look: MeshLook(_upload(await _whole(kinds[i])), plain),
          placements: placed[i],
          name: 'trees',
        ),
    ];
  }

  // ------------------------------------------------------------------ ground

  Future<RenderMaterial> _ground(StrategySimulation simulation) async {
    Future<Rgba8Image> swatch(String file) async =>
        shrinkSwatch(await _image(file), 128);
    final List<Building> halls = simulation.buildings;
    final List<ResourceNode> seams = simulation.resources;
    final Rgba8Image painted = await paintGround(
      ground: simulation.ground,
      swatches: GroundSwatches(
        grass: await swatch('grass.jpg'),
        meadow: await swatch('meadow.jpg'),
        earth: await swatch('dirt.jpg'),
        rock: await swatch('rock.jpg'),
        sand: await swatch('sand.jpg'),
      ),
      wear: <Wear>[
        for (final Building hall in halls)
          (
            x: hall.center.x,
            z: hall.center.z,
            halfWidth: hall.width / 2.0,
            halfDepth: hall.depth / 2.0,
            spread: 7.0,
          ),
        for (final ResourceNode seam in seams)
          (
            x: seam.at.x,
            z: seam.at.z,
            halfWidth: 1.5,
            halfDepth: 1.5,
            spread: 7.0,
          ),
      ],
      // Each hall's crowd wears a path to the seam nearest it.
      trails: <Trail>[
        for (final Building hall in halls)
          if (nearestSeam(hall, seams) case final ResourceNode seam)
            (
              fromX: hall.center.x,
              fromZ: hall.center.z,
              toX: seam.at.x,
              toZ: seam.at.z,
              width: 5.0,
            ),
      ],
      waterLevel: pondLevel,
    );
    final TextureHandle? texture = uploadRgba8(device, painted);
    // Filtered, and between mip levels too. Left to the backend's default the
    // painting is read texel by nearest texel: grass up close turns into a
    // mosaic of eight-centimetre squares, and from up high the far slopes
    // shimmer as the camera pans. The kits' palettes keep the default on
    // purpose — their swatches are meant to have hard edges.
    return RenderMaterial(
      lighting: LightingModel.pbr,
      albedo: texture,
      albedoSampler: SamplerDescriptor.trilinearRepeat,
      roughness: 0.95,
    );
  }

  // ------------------------------------------------------------------ images

  Future<Rgba8Image> _image(String file) async {
    final ByteData data = await rootBundle.load('$_textures/$file');
    final Rgba8Image? image = await defaultImageDecoder(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    if (image == null) throw StateError('$file did not decode');
    return image;
  }

  RenderMaterial _textured(Rgba8Image image) => RenderMaterial(
    lighting: LightingModel.pbr,
    albedo: uploadRgba8(device, image),
    roughness: 0.8,
  );

  DeviceMesh _upload(MeshData mesh) => DeviceMesh.upload(device, mesh);
}

/// [mesh] with every vertex's colour set to [color].
MeshData _coloured(MeshData mesh, Vector4 color) {
  final int stride = mesh.layout.floatsPerVertex;
  final int offset = mesh.layout.floatOffsetOf(VertexLayout.color.name);
  if (offset < 0) return mesh;
  final Float32List vertices = mesh.vertices;
  for (var o = offset; o < vertices.length; o += stride) {
    vertices[o] = color.x;
    vertices[o + 1] = color.y;
    vertices[o + 2] = color.z;
    vertices[o + 3] = color.w;
  }
  return mesh;
}

/// A copy of [image] with every strongly coloured texel whose hue lies near
/// [from] turned to the same distance from [to], in degrees.
///
/// Saturation is the guard: the palette's skin tones, wood and stone sit
/// close to red in hue but are pale or brown, and a repaint that caught them
/// would give the far side sunburnt soldiers. Only the swatches a kit uses
/// as its accent are saturated enough to move.
Rgba8Image _repaint(
  Rgba8Image image, {
  required double from,
  required double to,
}) {
  final Uint8List out = Uint8List.fromList(image.pixels);
  for (var at = 0; at < out.length; at += 4) {
    final double r = out[at] / 255.0;
    final double g = out[at + 1] / 255.0;
    final double b = out[at + 2] / 255.0;
    final double high = math.max(r, math.max(g, b));
    final double low = math.min(r, math.min(g, b));
    final double chroma = high - low;
    if (high <= 0.0 || chroma / high < 0.38) continue;
    final double hue = switch (high) {
      _ when high == r => 60.0 * (((g - b) / chroma) % 6.0),
      _ when high == g => 60.0 * ((b - r) / chroma + 2.0),
      _ => 60.0 * ((r - g) / chroma + 4.0),
    };
    var away = hue - from;
    if (away > 180.0) away -= 360.0;
    if (away < -180.0) away += 360.0;
    if (away.abs() > 22.0) continue;
    final double turned = (to + away) % 360.0;
    // Kept at the same value and pushed a little more saturated: the kit's
    // red swatch is stronger than its blue, and a red made at the blue's
    // saturation reads as pink.
    final double saturation = math.min(1.0, chroma / high * 1.45);
    final double c = high * saturation;
    final double x = c * (1.0 - ((turned / 60.0) % 2.0 - 1.0).abs());
    final double m = high - c;
    final (double rr, double gg, double bb) = switch (turned ~/ 60.0) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    out[at] = ((rr + m) * 255.0).round().clamp(0, 255);
    out[at + 1] = ((gg + m) * 255.0).round().clamp(0, 255);
    out[at + 2] = ((bb + m) * 255.0).round().clamp(0, 255);
  }
  return Rgba8Image(width: image.width, height: image.height, pixels: out);
}

/// [color] sRGB-encoded, as the `Vector4` this file paints with.
Vector4 _srgbVector(LinearColor color) {
  final srgb = color.toSrgb();
  return Vector4(srgb.r, srgb.g, srgb.b, srgb.a);
}
