/// A minimal check on a glTF/GLB export, for the invariants a writer must
/// never get wrong on its own. See `fmt-11`.
///
/// **Why a checker of our own rather than `npx gltf-validator`.** This
/// package resolves without the Flutter SDK and without `dart:io` (see
/// `gltf.dart`'s own doc comment) — reaching for a Node tool from `tool/ci.sh`
/// would mean the validation step depends on something this checkout's own
/// promise of "no SDK, no device" does not otherwise ask for. What Khronos's
/// validator checks and this one does not is a long list; what this checks is
/// the one thing a writer is trusted to get right and every reader silently
/// trusts it did: that an accessor's declared `min`/`max` is the data's own.
///
/// A reader is not required to recompute bounds — that is the whole point of
/// declaring them, culling and instancing code reads the accessor's `min`/
/// `max` rather than walking every vertex — so a wrong bound is invisible
/// until something built on it clips a triangle that was never actually
/// outside it.
library;

import 'dart:typed_data';

import '../asset_resolver.dart';
import 'glb_container.dart';
import 'gltf_accessor.dart';

/// Reads [bytes] as glTF/GLB and checks every accessor's declared `min`/`max`
/// against the values it actually holds.
///
/// [resolveUri] is only needed for a `.gltf` file with external buffers; a
/// self-contained `.glb` needs none. [tolerance] absorbs the float roundtrip
/// through JSON text, not a real disagreement — the writer this checks
/// against computes bounds in the same `double` precision it prints them in,
/// so a real bug moves a component by far more than this.
///
/// Returns one problem string per accessor component found wrong, empty when
/// nothing is. Accessors with no declared `min`/`max` are not required to
/// have one and are silently skipped, as are integer-component accessors —
/// this writer only ever puts bounds on `POSITION`, which is always `float`.
Future<List<String>> validateGltfExport(
  Uint8List bytes, {
  AssetUriResolver? resolveUri,
  double tolerance = 1e-5,
}) async {
  final container = GlbContainer.parse(bytes);
  final accessorsJson = container.json['accessors'];
  if (accessorsJson is! List) return const <String>[];

  final buffers = await container.resolveBuffers(resolveUri: resolveUri);
  final reader = GltfAccessorReader(json: container.json, buffers: buffers);

  final problems = <String>[];
  for (var i = 0; i < accessorsJson.length; i++) {
    final accessor = accessorsJson[i];
    if (accessor is! Map) continue;
    final declaredMin = accessor['min'];
    final declaredMax = accessor['max'];
    if (declaredMin is! List && declaredMax is! List) continue;
    if (!reader.hasBufferView(i)) continue;
    if (reader.componentTypeOf(i) != GltfComponentType.float) continue;

    final count = reader.countOf(i);
    if (count == 0) continue;
    final components = reader.typeOf(i).componentCount;
    final values = reader.readAsFloats(i);

    final actualMin = List<double>.filled(components, double.infinity);
    final actualMax = List<double>.filled(components, double.negativeInfinity);
    for (var e = 0; e < count; e++) {
      for (var c = 0; c < components; c++) {
        final v = values[e * components + c];
        if (v < actualMin[c]) actualMin[c] = v;
        if (v > actualMax[c]) actualMax[c] = v;
      }
    }

    if (declaredMin is List) {
      for (var c = 0; c < components && c < declaredMin.length; c++) {
        final declared = (declaredMin[c] as num).toDouble();
        if ((declared - actualMin[c]).abs() > tolerance) {
          problems.add(
            'accessors[$i].min[$c] says $declared but the data\'s own '
            'minimum is ${actualMin[c]}.',
          );
        }
      }
    }
    if (declaredMax is List) {
      for (var c = 0; c < components && c < declaredMax.length; c++) {
        final declared = (declaredMax[c] as num).toDouble();
        if ((declared - actualMax[c]).abs() > tolerance) {
          problems.add(
            'accessors[$i].max[$c] says $declared but the data\'s own '
            'maximum is ${actualMax[c]}.',
          );
        }
      }
    }
  }
  return problems;
}
