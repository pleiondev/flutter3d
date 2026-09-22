import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart' show PictureAnswer;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'diagnostic_renderer.dart';

PictureAnswer _ok(String says, [Uint8List? png]) =>
    (did: true, says: says, png: png);
PictureAnswer _refuse(String says) => (did: false, says: says, png: null);

/// Which pass a channel not finite, or a pixel darker than it should be, is
/// actually attributable to — stated once per [DiagnosticView] rather than
/// guessed per call, since it does not depend on the pixel.
String describePass(DiagnosticView view) => switch (view) {
  DiagnosticView.lit =>
    'the "scene" pass — the only stage that evaluates a material\'s '
        'lighting, a normal map included; composite and bloom only combine '
        'what the scene pass already wrote, so a wrong value here started '
        'there',
  DiagnosticView.normals =>
    'the "scene" pass\'s surface-buffer write — the only stage that fills '
        'that attachment. Note it encodes the mesh\'s own geometric normal, '
        'before any normal map perturbs it, so a broken tangent-space map '
        'never shows here even when it is exactly what is wrong with the '
        'lit view',
  DiagnosticView.shadowMap => 'the point-shadow pass, movers atlas',
  DiagnosticView.staticShadowMap => 'the point-shadow pass, static atlas',
};

/// One level open for diagnosis, and the last frame drawn of it — `par-02`.
///
/// **One frame at a time, the same discipline `SimSession` keeps.** `pixel`,
/// `passes` and `scanNaN` all read the frame `frame` last drew rather than
/// redrawing one of their own, so three calls describing "the same picture"
/// are guaranteed to mean it.
final class DiagnosticSession {
  DiagnosticRenderer? _renderer;
  DiagnosticFrame? _last;

  Future<PictureAnswer> open(String path) async {
    try {
      // No genre vocabulary: a frame's own normals, depth and NaNs are not a
      // property of any entity a level might spawn. A level whose entities
      // this empty registry does not know will fail `LevelValidator`'s own
      // check for it — the same trade a purely genre-agnostic tool makes
      // everywhere else in this session.
      final renderer = await DiagnosticRenderer.open(
        path,
        registry: EntityRegistry(const <EntityKind>[]),
      );
      _renderer = renderer;
      _last = null;
      return _ok('opened "$path" for diagnosis.');
    } catch (error) {
      return _refuse('could not open "$path": $error');
    }
  }

  Future<PictureAnswer> frame({
    required double atX,
    required double atY,
    required double atZ,
    required double aimX,
    required double aimY,
    required double aimZ,
    required DiagnosticView view,
  }) async {
    final renderer = _renderer;
    if (renderer == null) return _refuse('no level open — call open first');
    try {
      final drawn = await renderer.frame(
        at: Vector3(atX, atY, atZ),
        aim: Vector3(aimX, aimY, aimZ),
        view: view,
      );
      _last = drawn;
      return _ok(
        'a ${view.name} frame, ${drawn.width}x${drawn.height}, '
        '${drawn.png.length} bytes. Lighting for a lit frame runs entirely '
        'in ${describePass(view)}.',
        drawn.png,
      );
    } catch (error) {
      return _refuse('could not draw a frame: $error');
    }
  }

  /// The raw RGBA this view actually holds at ([x], [y]) — unclamped, so a
  /// depth past one metre or a NaN survives, unlike the picture.
  PictureAnswer pixel(int x, int y) {
    final frame = _last;
    if (frame == null) return _refuse('no frame drawn yet — call frame first');
    if (x < 0 || x >= frame.width || y < 0 || y >= frame.height) {
      return _refuse(
        'pixel ($x, $y) is outside the ${frame.width}x${frame.height} frame',
      );
    }
    final value = frame.rawAt(x, y);
    final words = <String, Object?>{
      'view': frame.view.name,
      'x': x,
      'y': y,
      'rgba': <double>[value.x, value.y, value.z, value.w],
      'pass': describePass(frame.view),
    };
    if (frame.view == DiagnosticView.normals) {
      final normal = decodeOctahedralNormal(value.x, value.y);
      words['normal'] = <double>[normal.x, normal.y, normal.z];
      words['roughness'] = value.z;
      words['viewDepthMetres'] = value.w;
    }
    return _ok(jsonEncode(words));
  }

  /// Every pass the frame graph kept for the last frame drawn, in the order
  /// it ran — `FrameResult.passes`, read back rather than recomputed.
  PictureAnswer passes() {
    final frame = _last;
    if (frame == null) return _refuse('no frame drawn yet — call frame first');
    return _ok(
      jsonEncode(<Map<String, Object?>>[
        for (final pass in frame.passes)
          <String, Object?>{
            'name': pass.name,
            'active': pass.active,
            'micros': pass.micros,
            // `gfx-01n`: an agent asking why a frame is slow gets the same
            // four numbers a person reads off the panel, rather than a time
            // it has to guess the cause of.
            'drawCalls': pass.drawCalls,
            'triangles': pass.triangles,
            'pipelineSwitches': pass.pipelineSwitches,
          },
      ]),
    );
  }

  /// The first pixel in the last frame drawn whose value is not finite, and
  /// which pass is answerable for a channel like that ever reaching the
  /// frame at all.
  PictureAnswer scanNaN() {
    final frame = _last;
    if (frame == null) return _refuse('no frame drawn yet — call frame first');
    final hit = frame.firstNonFinite();
    if (hit == null) {
      return _ok('no NaN or infinity anywhere in the ${frame.view.name} view.');
    }
    const channels = <String>['R', 'G', 'B', 'A'];
    return _ok(
      'the ${frame.view.name} view is not finite at (${hit.x}, ${hit.y}), '
      'channel ${channels[hit.channel]}. That value came out of '
      '${describePass(frame.view)}.',
    );
  }
}
