import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'editing.dart';
import 'gizmos.dart';
import 'looks.dart';

/// Diagnostic: what to draw besides the walls, the floor and the ceiling.
///
///  * `--dart-define=only=level` — nothing at all, and none of the document's
///    lights either.
///  * `--dart-define=only=lights` — the lights, and marks for the things that
///    emit them: a handle the document calls a light, and an entity the game
///    described a silhouette for.
const String _only = String.fromEnvironment('only');
const bool kLevelOnly = _only == 'level';
const bool kLightsOnly = _only == 'lights';

/// Draws everything about a level that the renderer does not: the selection
/// box, a mark for anything with no geometry, and — once a model has read —
/// the model in place of the mark.
///
/// **Pulled out of `_EditorScreenState`, and belongs beside the render loop
/// rather than in `EditorCubit`.** Every method here runs off the back of a
/// scene rebuild, not off a keystroke a screen needs to show — the marker
/// moves when the selection does, but nothing in this class is text on a
/// panel. It is handed a device once and the document, the looks and the
/// hidden set every time something changes; it owns the nodes it puts into the
/// scene and nothing about why they changed.
final class SceneDressing {
  SceneDressing(this.device);

  final GraphicsDevice device;

  /// The box drawn around whatever is selected.
  ///
  /// A node of its own rather than a highlight on the level's geometry —
  /// see the field this replaced in `_EditorScreenState` for why: the level
  /// is not one node per brush, and this is the one thing in the scene that
  /// is not the document.
  SceneNode? marker;

  final List<SceneNode> gizmos = <SceneNode>[];

  /// Every map the level named, already uploaded by the loader. What lets a
  /// door be drawn in the iron the document says it is made of.
  Map<String, TextureHandle?> textures = const <String, TextureHandle?>{};

  /// Models named by entities, loaded once each.
  ///
  /// **Keyed by the path the document wrote**, so two hundred and sixty-one
  /// coins are one file read and one upload.
  final Map<String, Future<ModelAsset?>> _models =
      <String, Future<ModelAsset?>>{};

  /// Forgets everything drawn for the previous document. Called at the start
  /// of every scene rebuild.
  void reset() {
    marker = null;
    gizmos.clear();
  }

  /// Puts the selection box around whatever is selected, or takes it away.
  ///
  /// **Two marks, because one of them is useless half the time.** The engine
  /// draws twelve lines around anything handed to `RenderSettings.highlighted`,
  /// which is right for a brush somebody is standing inside and nearly
  /// invisible for a small brush across a dark room. So the node is also
  /// drawn, in a colour nothing in a crypt is and lit by itself so a dark
  /// corridor cannot swallow it.
  void placeMarker(Scene scene, Editing editing) {
    if (kLevelOnly) return;

    final was = marker;
    if (was != null) scene.remove(was);
    marker = null;

    final at = editing.where;
    if (at == null) return;
    final size = editing.brush?.size ?? Vector3.all(kGizmoSize);

    // **A cage, not a solid box.** A wall is six metres by five, and a glowing
    // slab that size over the thing somebody just selected hides both it and
    // the room. Edges show the same extent and hide nothing.
    marker = buildCage(
      scene,
      at,
      size * 1.06,
      Vector3(1.0, 0.45, 0.05),
      name: 'selection',
    );
  }

  /// Draws a mark for everything the renderer does not.
  ///
  /// **Half a level is invisible to a level editor, and it is the half that
  /// makes it a level.** Geometry draws itself; a monster, a lift, a door, a
  /// trigger and the point the player starts at are coordinates in a document,
  /// and a light is a coordinate that changes other things and shows nothing
  /// of itself.
  ///
  /// Their colours come from the type's own name — see [tintFor] — because
  /// this application is not allowed to know what a `monster` is.
  void placeGizmos(
    Scene scene,
    Editing editing, {
    required Looks looks,
    required Set<String> hidden,
  }) {
    if (kLevelOnly) return;

    for (final gizmo in gizmos) {
      scene.remove(gizmo);
    }
    gizmos.clear();

    for (final handle in handlesOf(editing.level, looks: looks)) {
      if (handle.kind == Piece.brush) continue;
      final entity = handle.kind == Piece.entity
          ? editing.level.entities[handle.index]
          : null;
      if (kLightsOnly &&
          handle.kind != Piece.light &&
          (entity == null || looks.partsFor(entity).isEmpty)) {
        continue;
      }
      if (hidden.contains(entity?.type ?? 'light')) continue;

      // **Drawn as what it is, when the document says what it is.** A door
      // names a material the level already loaded, and a lift names the size
      // it moves at. What has neither gets the mark.
      final named = entity?.string('material');
      final isLight = handle.kind == Piece.light;
      final material = named == null ? null : editing.level.materials[named];

      // A silhouette the game described: a torch's plate, shaft, cup and
      // flame, built out of the engine's own primitives. Drawn instead of the
      // mark, not beside it.
      final parts = entity == null ? const <Part>[] : looks.partsFor(entity);
      if (parts.isNotEmpty) {
        buildParts(scene, parts, handle, entity!);
        continue;
      }

      // **A region is drawn as its edges.** A trigger four metres wide, filled
      // in, is a wall in front of whatever it was placed around.
      //
      // **A sized thing that names a material is not a region.** Both carry
      // their own size, and what tells them apart without knowing either word
      // is that one says what it is made of.
      if (handle.volume && material == null) {
        gizmos.add(buildCage(scene, handle.centre, handle.size, handle.tint));
        continue;
      }

      final node =
          MeshNode(
              // **A light is a ball, everything else is a box.**
              isLight
                  ? SharedMeshes(device).shape(
                      'gizmo-light',
                      () => SphereShape(radius: kGizmoSize * 0.45),
                    )
                  : SharedMeshes(device).box(handle.size),
              material == null
                  ? engine.Material(
                      name: 'gizmo',
                      baseColor: Vector4(
                        handle.tint.x,
                        handle.tint.y,
                        handle.tint.z,
                        1.0,
                      ),
                      // Lit by itself, or a mark in an unlit corner is a mark
                      // nobody can find.
                      emissive: handle.tint * 0.9,
                    )
                  : LevelLoader.materialFrom(material, textures, name: named),
              name: 'gizmo',
            )
            ..setPosition(handle.centre.x, handle.centre.y, handle.centre.z)
            ..castsShadow = false;
      if (entity != null && entity.yaw != 0.0) {
        node.setRotation(
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), entity.yaw),
        );
      }
      scene.add(node);
      gizmos.add(node);
    }
  }

  /// The twelve edges of a region, as thin bars.
  ///
  /// Thin in proportion to the region rather than a fixed thickness: a
  /// trigger is metres across and a small volume is centimetres, and one
  /// width cannot be visible on the first and slender on the second.
  SceneNode buildCage(
    Scene scene,
    Vector3 centre,
    Vector3 size,
    Vector3 tint, {
    String name = 'gizmo',
  }) {
    final holder = SceneNode(name: name)
      ..setPosition(centre.x, centre.y, centre.z);
    scene.add(holder);
    final bar = math.max(
      0.02,
      math.min(size.x, math.min(size.y, size.z)) * 0.05,
    );
    final half = Vector3(size.x / 2.0, size.y / 2.0, size.z / 2.0);
    final meshes = SharedMeshes(device);
    final material = engine.Material(
      name: name,
      baseColor: Vector4(tint.x, tint.y, tint.z, 1.0),
      emissive: tint * 0.9,
    );

    void edge(Vector3 extent, double x, double y, double z) {
      holder.add(
        MeshNode(meshes.box(extent), material, name: 'edge')
          ..setPosition(x, y, z)
          ..castsShadow = false,
      );
    }

    // **The bars meet, they do not overlap.** Twelve full-length bars share a
    // small cube at each corner, and two coplanar faces of the same colour
    // fight for those pixels. The four along X keep their length and the
    // other eight give up a bar's width at each end, so the corner belongs to
    // one of them.
    for (final y in <double>[-half.y, half.y]) {
      for (final z in <double>[-half.z, half.z]) {
        edge(Vector3(size.x, bar, bar), 0.0, y, z);
      }
    }
    for (final x in <double>[-half.x, half.x]) {
      for (final z in <double>[-half.z, half.z]) {
        edge(Vector3(bar, math.max(size.y - bar * 2, bar), bar), x, 0.0, z);
      }
    }
    for (final x in <double>[-half.x, half.x]) {
      for (final y in <double>[-half.y, half.y]) {
        edge(Vector3(bar, bar, math.max(size.z - bar * 2, bar)), x, y, 0.0);
      }
    }
    return holder;
  }

  /// Puts one described silhouette into the scene.
  ///
  /// Under a holder at the entity's place, turned by its yaw, so a part's
  /// position is written the way the game writes it: local +Z into the wall.
  void buildParts(
    Scene scene,
    List<Part> parts,
    Handle handle,
    EntityDef entity,
  ) {
    final holder = SceneNode(name: 'gizmo')
      ..setPosition(handle.centre.x, handle.centre.y, handle.centre.z)
      ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), entity.yaw));
    scene.add(holder);
    gizmos.add(holder);

    final meshes = SharedMeshes(device);
    for (final part in parts) {
      final node = MeshNode(
        _meshFor(meshes, part),
        engine.Material(
          name: part.glows ? 'flame' : 'part',
          baseColor: Vector4(part.colour.x, part.colour.y, part.colour.z, 1.0),
          // A flame is the light rather than the thing holding it, and a dark
          // corridor would otherwise swallow the one part that is the point.
          emissive: part.glows ? part.colour * 1.4 : null,
        ),
        name: part.shape,
      )..setPosition(part.at.x, part.at.y, part.at.z);
      if (part.pitch != 0.0) {
        node.setRotation(
          Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), part.pitch),
        );
      }
      node.castsShadow = false;
      holder.add(node);
    }
  }

  static DeviceMesh _meshFor(SharedMeshes meshes, Part part) =>
      switch (part.shape) {
        'cylinder' => meshes.shape(
          'part-cyl-${part.radius}-${part.height}',
          () => CylinderShape(
            radiusTop: part.radius,
            radiusBottom: part.radius,
            height: part.height,
          ),
        ),
        'cone' => meshes.shape(
          'part-cone-${part.radius}-${part.height}',
          () => ConeShape(radius: part.radius, height: part.height),
        ),
        'sphere' => meshes.shape(
          'part-ball-${part.radius}',
          () => SphereShape(radius: part.radius),
        ),
        _ => meshes.box(part.size),
      };

  /// Replaces the marks of everything that names a model with the model.
  ///
  /// **After the boxes rather than instead of them**, because a glTF takes
  /// long enough to read that a level would appear empty while it happened.
  /// The box goes down first, the model replaces it when it arrives, and a
  /// model that will not read leaves the box.
  ///
  /// [stillCurrent] answers whether the scene this was called for is still the
  /// one on screen — a keypress is faster than a glTF, and putting a model
  /// into a scene nobody draws any more is the platformer's own bug, written
  /// down in its `_dressRunner`.
  Future<void> dressGizmos(
    Scene scene,
    Editing editing, {
    required Looks looks,
    required Set<String> hidden,
    required String? assetRoot,
    required bool Function() stillCurrent,
  }) async {
    if (kLevelOnly || kLightsOnly) return;
    final root = assetRoot;
    if (root == null) return;

    for (final handle in handlesOf(editing.level, looks: looks)) {
      if (handle.kind != Piece.entity) continue;
      final entity = editing.level.entities[handle.index];
      // What the entity says, else what the game says this type is.
      if (hidden.contains(entity.type)) continue;
      final path = looks.modelFor(entity);
      if (path == null) continue;

      final asset = await _models.putIfAbsent(
        path,
        () => _loadModel(device, '$root/$path'),
      );
      if (!stillCurrent()) return;
      // **One model that will not read is one mark left as a box**, and it
      // used to be every mark after it: this was a `return`, so the first
      // missing file ended the loop and everything later in the level stayed
      // a coloured cube with no clue as to why.
      if (asset == null) continue;

      final instance = asset.instantiate(scene, name: 'model');

      // Diagnostic: `--dart-define=skinned=off` leaves anything with a rig as
      // its mark, and `--dart-define=skip=a,b` leaves those types as theirs.
      if (const String.fromEnvironment('skinned') == 'off' &&
          asset.skins.isNotEmpty) {
        continue;
      }
      if (const String.fromEnvironment(
        'skip',
      ).split(',').contains(entity.type)) {
        continue;
      }

      // **Posed, or it stands there like a scarecrow.** A skinned model in a
      // file is in its bind pose, because that is the shape a rig is authored
      // in and no exporter saves a "resting" one.
      //
      // So does this, once, and never again: nothing here animates, and a
      // model frozen on the first frame of a resting clip is what somebody
      // placing it wants to see.
      //
      // "Idle" is not a word about any genre — it is what an animator calls
      // the clip a character plays when it is doing nothing. Anything without
      // one takes its first clip, which is still a pose somebody authored
      // rather than the rig's.
      final player = instance.player;
      final clips = player?.clipNames ?? const <String>[];
      if (player != null && clips.isNotEmpty) {
        final resting = clips.indexWhere(
          (String name) => name.toLowerCase().contains('idle'),
        );
        player.play(resting < 0 ? 0 : resting);
      }

      instance.root
        ..setPosition(handle.centre.x, handle.centre.y, handle.centre.z)
        ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), entity.yaw));
      gizmos.add(instance.root);
      // The mark it stands in for. Found by where it is, because that is what
      // the two have in common and the list is short.
      for (final gizmo in gizmos) {
        if (gizmo.name != 'gizmo') continue;
        final at = gizmo.localMatrix.getTranslation();
        if ((at - handle.centre).length2 < 1e-6) {
          gizmo.visible = false;
          break;
        }
      }
    }
  }

  static Future<ModelAsset?> _loadModel(
    GraphicsDevice device,
    String path,
  ) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: FileAssetSource(path)),
      );
      return await ModelAsset.fromDocument(
        document,
        device: device,
        name: path,
      );
    } catch (error) {
      debugPrint('editor: could not read the model "$path" ($error)');
      return null;
    }
  }
}
