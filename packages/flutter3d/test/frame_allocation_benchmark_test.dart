/// What a frame costs on the software backend: its draw calls, and the
/// objects the Dart heap allocated for it once the renderer is warm, told
/// apart by who allocated them.
///
///     flutter test --enable-vmservice --tags benchmark --run-skipped \
///         test/frame_allocation_benchmark_test.dart
///
/// **The allocations are the VM's own count, not an estimate.** The test
/// connects to the service of the isolate it runs in and traces every class
/// of the program, so each object allocated is a sample with its stack; it
/// draws one frame with nothing awaited around it and counts the samples.
/// The VM's per-class totals (`getAllocationProfile`) cannot stand in for
/// this: they are read off the live heap, and a frame's garbage is dead by
/// then. Without `--enable-vmservice` there is no service to ask, and the
/// test says so and skips rather than inventing a number.
///
/// **One frame to a window, and a small one,** because the samples share the
/// profiler's ring buffer, about 41 000 entries on a desktop VM, and a frame
/// that overflowed it would lose its first allocations without a word. The
/// software rasteriser shades on the CPU, so its own vertex and fragment
/// stages are most of a frame's objects; they are counted apart as
/// `shading`, and what the renderer, the frame graph and the encoder
/// allocate (`engine`) is held to its own number, since that is the part
/// every backend pays.
///
/// **The scene moves every frame**: one box turns, so the cascades that hold
/// it are keyed again and redrawn, and every cache that keys on the scene's
/// changes is asked again. A scene that stands still would measure the
/// held-frame path and nothing else.
///
/// **The baseline** is [_baseline], measured on the named machine and SDK and
/// written with the date. Draw calls are exact. Allocations hold to [_margin]
/// above the baseline, because the JIT's choices (an inlined closure, a
/// double kept boxed or not) move them a little between SDKs; three windows
/// on one machine agree to half a per cent, and a change that allocates per
/// draw again moves them by far more than the margin. When a frame allocates
/// less, the baseline is lowered here, with the date, so it cannot creep
/// back.
@Tags(<String>['benchmark'])
library;

import 'dart:developer';
import 'dart:isolate';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' hide Isolate;
import 'package:vm_service/vm_service_io.dart';

/// Frames drawn before the count starts, untraced: pipelines compiled, the
/// frame graph built, the pools filled, the shadow atlas made, the JIT given
/// its chance.
const int _warmUp = 60;

/// Frames drawn traced before the first window, so code the tracing sends
/// back to the compiler is compiled again first.
const int _tracedWarmUp = 2;

/// Windows of one frame; the least is the frame's cost.
const int _windows = 3;

const int _width = 16;
const int _height = 9;

/// The defaults but a small atlas: what is counted here is per draw and per
/// pass, and the software rasteriser's objects grow with its texels.
const RenderSettings _settings = RenderSettings(
  shadows: ShadowSettings(resolution: 16, cubeResolution: 8),
);

/// The numbers this scene is held to.
///
/// Measured on 2026-10-11 on an Apple M3 Pro, Flutter 3.44 (`flutter test`'s
/// JIT), before the ECS query and the shadow keys stopped allocating.
const ({int drawCalls, int engine, int shading}) _baseline = (
  drawCalls: 31,
  engine: 4342,
  shading: 29801,
);

/// How far above [_baseline] a frame's allocations may land.
const double _margin = 0.10;

/// A floor, six boxes, one of which turns, and a sun casting through three
/// cascades.
({Scene scene, CameraNode camera, MeshNode turning}) _scene(CpuDevice device) {
  final scene = Scene();
  MeshNode block(Vector3 size, Vector3 at, {required String name}) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    RenderMaterial(
      name: name,
      baseColor: LinearColor.fromSrgb(0.7, 0.7, 0.75, 1.0),
      lighting: LightingModel.pbr,
      roughness: 0.6,
    ),
    name: name,
  )..setPosition(at.x, at.y, at.z);

  scene.add(block(Vector3(30, 1, 30), Vector3(0, -0.5, 0), name: 'floor'));
  late final MeshNode turning;
  for (var i = 0; i < 6; i++) {
    final box = block(
      Vector3(1.5, 2.0, 1.5),
      Vector3(i * 3.0 - 7.5, 1.0, 3.0),
      name: 'box$i',
    );
    if (i == 2) turning = box;
    scene.add(box);
  }
  scene.add(
    LightNode(
      type: LightType.directional,
      intensity: LightNode.defaultIntensity,
      castsShadow: true,
      name: 'sun',
    )..setLocalForward(Vector3(-0.3, -0.9, 0.2)),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 4.0, -14.0)
    ..lookAt(Vector3(0.0, 1.0, 0.0));
  return (scene: scene, camera: camera, turning: turning);
}

final RegExp _package = RegExp(r'/(flutter3d\w*)/lib/(?:src/)?(\w+)');

/// Who allocated a sample: the innermost frame of its stack outside the SDK
/// and `vector_math`, named by its package, with the software backend split
/// into its encoder and its shading.
String _owner(CpuSample sample, List<ProfileFunction> functions) {
  for (final index in sample.stack ?? const <int>[]) {
    final url = functions[index].resolvedUrl ?? '';
    if (url.isEmpty ||
        url.startsWith('dart:') ||
        url.startsWith('org-dartlang-sdk:') ||
        url.contains('/vector_math')) {
      continue;
    }
    final match = _package.firstMatch(url);
    if (match == null) return 'other';
    final package = match[1]!;
    if (package != 'flutter3d_cpu') return package;
    return switch (match[2]!) {
      'cpu_encoder' || 'cpu_device' => 'flutter3d_cpu encoder',
      _ => 'flutter3d_cpu shading',
    };
  }
  return 'other';
}

/// One window's count, by class and by owner.
final class _Window {
  _Window(this.drawCalls);

  final int drawCalls;
  final Map<String, int> classes = <String, int>{};
  final Map<String, int> owners = <String, int>{};

  int get total => owners.values.fold<int>(0, (sum, count) => sum + count);

  int get shading => owners['flutter3d_cpu shading'] ?? 0;

  int get engine => total - shading - (owners['other'] ?? 0);
}

void main() {
  test('a warm frame allocates no more than its baseline', () async {
    final uri = (await Service.getInfo()).serverWebSocketUri;
    if (uri == null) {
      markTestSkipped(
        'no VM service to count allocations with: run with '
        '--enable-vmservice',
      );
      return;
    }
    final service = await vmServiceConnectUri(uri.toString());
    addTearDown(service.dispose);
    final isolateId = Service.getIsolateId(Isolate.current)!;

    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    );
    final room = _scene(it.device);
    final views = <CameraView>[CameraView(camera: room.camera)];
    var frame = 0;
    int draw() {
      frame++;
      room.turning.setRotationYawPitchRoll(frame * 0.05, 0.0, 0.0);
      return renderer
          .render(
            width: _width,
            height: _height,
            scene: room.scene,
            views: views,
            settings: _settings,
          )
          .drawCalls;
    }

    for (var i = 0; i < _warmUp; i++) {
      draw();
    }

    // Every class with a library traced; the ones without are the VM's own
    // code, inline caches and the like, which the JIT makes and no change to
    // the renderer can. The service client's classes are left out too.
    final profile = await service.getAllocationProfile(isolateId);
    final names = <int, String>{
      for (final stats in profile.members ?? const <ClassHeapStats>[])
        if (stats.classRef case ClassRef(
          :final id?,
          library: LibraryRef(uri: final library?),
          :final name?,
        ) when !library.startsWith('package:vm_service'))
          int.parse(id.substring(id.lastIndexOf('/') + 1)): '$library $name',
    };
    await Future.wait(<Future<Success>>[
      for (final id in names.keys)
        service.setTraceClassAllocation(isolateId, 'classes/$id', true),
    ]);
    for (var i = 0; i < _tracedWarmUp; i++) {
      draw();
    }

    Future<_Window> window() async {
      await service.clearCpuSamples(isolateId);
      final counted = _Window(draw());
      final traces = await service.getAllocationTraces(isolateId);
      final functions = traces.functions ?? const <ProfileFunction>[];
      for (final sample in traces.samples ?? const <CpuSample>[]) {
        final name = names[sample.classId] ?? '${sample.classId}';
        counted.classes.update(name, (n) => n + 1, ifAbsent: () => 1);
        counted.owners.update(
          _owner(sample, functions),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
      return counted;
    }

    // The least of a few windows. The JIT keeps optimising in the background
    // after the warm-up, and code it has not optimised yet allocates doubles
    // and vectors that optimised code keeps in registers. Noise of that kind
    // only ever adds, so the smallest window is the frame's own cost.
    var best = await window();
    for (var i = 1; i < _windows; i++) {
      final next = await window();
      if (next.total < best.total) best = next;
    }

    // ignore: avoid_print — the numbers are the point of this file.
    print(
      'per frame: ${best.drawCalls} draw calls, ${best.total} objects: '
      '${best.engine} engine, ${best.shading} shading',
    );
    for (final MapEntry(key: owner, value: count)
        in best.owners.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value))) {
      // ignore: avoid_print — and who allocates them.
      print('  $owner: $count');
    }
    for (final MapEntry(key: name, value: count)
        in (best.classes.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(20)) {
      // ignore: avoid_print — and of what.
      print('  $name: $count');
    }

    expect(best.drawCalls, _baseline.drawCalls);
    expect(
      best.engine,
      lessThanOrEqualTo((_baseline.engine * (1 + _margin)).round()),
      reason: 'objects the renderer, the graph and the encoder allocate',
    );
    expect(
      best.shading,
      lessThanOrEqualTo((_baseline.shading * (1 + _margin)).round()),
      reason: "objects the software rasteriser's stages allocate",
    );
  });
}
