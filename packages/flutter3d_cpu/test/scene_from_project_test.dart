/// `sceneFromProject` hangs a child under its parent, so a child under a
/// moved parent is drawn where the viewport draws it — and a snapshot draws on
/// the device its caller hands it.
///
///     dart test test/scene_from_project_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  test('a child is placed through its parent, not from the world origin', () {
    // Listed child first on purpose: a builder that attaches in one pass
    // would find no parent node yet and hang the child off the scene.
    final project = ModelProject(
      objects: <ModelObject>[
        ModelObject(
          id: 2,
          name: 'child',
          geometry: const SocketGeometry(),
          transform: Matrix4.translation(Vector3(0, 1, 0)),
          parent: 1,
        ),
        ModelObject(
          id: 1,
          name: 'parent',
          geometry: const SocketGeometry(),
          transform: Matrix4.translation(Vector3(3, 0, 0)),
        ),
      ],
      nextId: 3,
    );

    final scene = sceneFromProject(project, _cpuDevice(4, 4));
    final child = scene.meshes.firstWhere((MeshNode m) => m.name == 'child');

    // Mutation: attach every object to the scene root. The child then stands
    // at (0, 1, 0), three metres from where the viewport draws it.
    expect(child.parent?.name, 'parent');
    final at = child.worldMatrix.getTranslation();
    expect(at.x, closeTo(3, 1e-6));
    expect(at.y, closeTo(1, 1e-6));
  });

  test('a snapshot renders on the device a caller hands it', () async {
    final sizes = <(int, int)>[];
    GraphicsDevice counting(int width, int height) {
      sizes.add((width, height));
      return _cpuDevice(width, height);
    }

    final job = RenderSnapshotJob(
      ModelProject(
        objects: <ModelObject>[
          ModelObject(
            id: 1,
            name: 'mark',
            geometry: const SocketGeometry(),
            transform: Matrix4.identity(),
          ),
        ],
        nextId: 2,
      ),
      RenderPreset(
        width: 8,
        height: 8,
        camera: SnapshotCamera(
          position: Vector3(0, 0, 3),
          target: Vector3.zero(),
        ),
      ),
      tileDevice: counting,
    );
    // One chunk at a time, on this isolate, so the factory's own calls are
    // visible — `run` on native sends the factory to another isolate.
    for (var index = 0; index < job.chunkCount; index++) {
      await job.renderTile(index);
    }
    job.finish();

    // Mutation: build a device inside the job. The factory is never asked
    // and a caller's device is silently ignored.
    expect(sizes, hasLength(job.chunkCount));
  });
}
