/// A sky: a gradient overhead instead of one flat colour behind everything.
///
/// What this replaces is `RenderView.clearColor`, which is a single colour and
/// therefore the same colour whichever way the camera turns. That is fine for a
/// dungeon and wrong for anywhere outdoors, where the difference between
/// looking towards the sun and away from it is most of what tells a player
/// where they are.
///
/// **This is a mesh, not a feature.** No new shader, no texture, no backend
/// work: the sky is an inside-out sphere with its colour baked into the `color`
/// vertex attribute, which `VertexLayout.standard` already carries,
/// `lib/surface.glsl` already multiplies into albedo, and `unlit.frag` already
/// emits as light. Everything it needs from the renderer was added for it and
/// is ordinary: [Material.drawBucket] to be drawn first, [Material.depthWrite]
/// to leave the depth buffer alone, and `MeshNode.castsShadow` /
/// `frustumCulled` to stay out of the two places a mesh the size of the world
/// would otherwise hurt.
///
/// **Why it is small and follows the camera.** Fog is applied on world distance
/// inside `WriteSurface`, and there is no way out of it without a shader of its
/// own — so a dome a kilometre across arrives as very nearly pure fog colour,
/// which is exactly the flat background it was meant to replace. Ten metres of
/// air changes almost nothing, so the gradient survives. A small dome has to
/// move with the camera or it is a ball on the ground; [followCamera] is that,
/// and it is a call the application makes each frame, in the open, rather than
/// a hidden update nobody can find when it goes wrong.
///
/// ```dart
/// final sky = skyNode(DeviceMesh.upload(device, SkyDome().build()));
/// paintSky(sky.mesh, SkyGradient(
///   zenith: Vector3(0.10, 0.22, 0.52),
///   horizon: Vector3(0.62, 0.71, 0.82),
///   nadir: Vector3(0.08, 0.08, 0.09),
/// ));
/// scene.add(sky);
/// // once a frame, after the camera has moved:
/// followCamera(sky, camera);
/// ```
///
/// **Colours here are linear.** This is the one way the sky differs from the
/// clear colour it replaces: `RenderView.clearColor` is authored in sRGB and
/// decoded by the renderer, while a vertex colour is linear by the glTF spec
/// and used as it is. The same numbers give a lighter sky. Halving each channel
/// is a good first guess; measuring is better.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../geometry/lathe_shape.dart';
import '../geometry/mesh_data.dart';
import '../geometry/mesh_geometry.dart';
import '../geometry/shape.dart';
import '../geometry/vertex_layout.dart';
import '../render/lighting_model.dart';
import '../render/material.dart';
import 'camera_node.dart';
import 'mesh_node.dart';
import 'sky_gradient.dart';

/// An inside-out sphere, which is a sky the camera sits at the centre of.
///
/// Small on purpose — see the library docstring: a large one is eaten by the
/// fog. Ten metres clears any sensible near plane and is far short of any
/// sensible far plane, so it neither clips at the eye nor sorts oddly.
///
/// [rings] and [segments] decide how smooth the gradient is, and smooth is all
/// they buy: the colour is per vertex, so a coarse dome gives visible bands
/// exactly where the gradient changes fastest.
final class SkyDome extends Shape {
  const SkyDome({
    this.radius = 10.0,
    this.rings = 24,
    this.segments = 32,
    this.name = 'sky',
  });

  final double radius;
  final int rings;
  final int segments;

  @override
  final String name;

  @override
  MeshData build({VertexLayout layout = VertexLayout.standard}) {
    // Top to bottom, which reverses the profile and so turns the surface
    // inside out — normals in, front faces in. `LatheShape` documents this as
    // the way to build a skybox and it is the whole reason no new geometry
    // code is needed here.
    final profile = <Vector2>[
      for (var i = 0; i <= rings; i++)
        () {
          final angle = math.pi * i / rings;
          return Vector2(radius * math.sin(angle), radius * math.cos(angle));
        }(),
    ];

    return LatheShape(
      profile: profile,
      segments: segments,
      name: name,
    ).build(layout: layout);
  }
}

/// Writes [colour] into every vertex of [mesh], by the direction it sits in.
///
/// In place, on the CPU mesh, before it is uploaded: the sky is baked once and
/// costs nothing per frame. Changing the hour means painting again and
/// re-uploading, which is the honest cost of having no shader.
///
/// Throws if the mesh has no colour attribute, because the alternative is a sky
/// that silently comes out white — `MeshBuilder` fills an unset colour with
/// opaque white, precisely so that a mesh nobody painted still draws.
void paintSky(MeshData mesh, SkyColour colour) {
  final offset = mesh.layout.floatOffsetOf(VertexLayout.color.name);
  if (offset < 0) {
    throw ArgumentError(
      'the sky mesh has no colour attribute, so there is nowhere to put the '
      'gradient; build it with VertexLayout.standard',
    );
  }
  final position = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  if (position < 0) {
    throw ArgumentError('the sky mesh has no positions');
  }

  final stride = mesh.layout.floatsPerVertex;
  // One instance for the whole mesh; see [SkyLook].
  final look = SkyLook();
  final direction = look.direction;
  for (var base = 0; base < mesh.vertices.length; base += stride) {
    direction.setValues(
      mesh.vertices[base + position],
      mesh.vertices[base + position + 1],
      mesh.vertices[base + position + 2],
    );
    final length = direction.length;
    // A vertex at the centre has no direction. A lathe never puts one there,
    // but a caller may pass any mesh and the answer to "what colour is no
    // direction" is the horizon rather than a division by zero.
    if (length > 1e-9) {
      direction.scale(1.0 / length);
    } else {
      direction.setValues(0.0, 0.0, 1.0);
    }

    final rgba = colour(look);
    mesh.vertices[base + offset] = rgba.x;
    mesh.vertices[base + offset + 1] = rgba.y;
    mesh.vertices[base + offset + 2] = rgba.z;
    mesh.vertices[base + offset + 3] = rgba.w;
  }
}

/// A node holding [mesh], flagged so that it behaves as a sky.
///
/// A function rather than a subclass: `MeshNode` is `final`, and it is final for
/// a good reason — the renderer reads its fields directly on the hot path. What
/// would have been a class is four flags, and they are worth naming because
/// each one is a distinct thing that goes wrong without it:
///
/// * `drawBucket = -1` — drawn before the scene. Ordinary materials sit at
///   zero, so this is the only way to be first, and first is where a backdrop
///   has to be.
/// * `depthWrite = false` — drawn, then not there. Ten metres of sky would
///   otherwise write depth across the frame and clip the entire level away.
/// * `castsShadow = false` — a sphere around the camera casts no shadow, and
///   would otherwise be drawn into every cascade.
/// * `frustumCulled = false` — its bounds move with the camera every frame and
///   describe a ball around it, which is not a useful thing to cull against.
///
/// [Material.depthCompare] is deliberately **not** set. The sky goes first, so
/// the depth buffer it is tested against is the cleared one and `less` passes
/// on its own; asking for `always` would be a state change emitted every frame
/// to buy nothing.
MeshNode skyNode(MeshGeometry mesh, {String name = 'sky'}) =>
    MeshNode(
        mesh,
        Material(
          name: name,
          lighting: LightingModel.unlit,
          drawBucket: -1,
          depthWrite: false,
        ),
        name: name,
      )
      ..castsShadow = false
      ..frustumCulled = false;

/// Moves [sky] to where [camera] is, which is what makes a ten-metre sphere a
/// sky rather than a ball.
///
/// Position only: rotating it would rotate the gradient with the camera, and
/// the whole point of a sky is that it does not move when you turn your head.
///
/// Called by the application once a frame, after the camera has been placed and
/// before the frame is drawn. In the open rather than hidden inside the
/// renderer, because a sky that lags the camera by a frame is a sky that shows
/// its own edge on a fast pan, and a bug like that needs to be findable in the
/// code that causes it.
void followCamera(MeshNode sky, CameraNode camera) {
  final at = camera.readWorldPosition();
  sky.setPosition(at.x, at.y, at.z);
}
