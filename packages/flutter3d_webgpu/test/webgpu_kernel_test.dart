/// `.f3dmat compute` on WebGPU: a bundle's kernel section loads as compute
/// stages, translated to WGSL by `flutter3d_shaders`, with the bindings the
/// pipeline layout is built from; a reload compiles a kernel in use again.
///
/// Runs on both platforms, as `webgpu_loaded_shaders_test.dart` does: the
/// translation and the reflection are decided before anything touches a GPU.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/kernel.dart';
import 'package:flutter3d_webgpu/src/webgpu_compute_stage.dart';
import 'package:flutter3d_webgpu/src/webgpu_loaded_shaders.dart';
import 'package:flutter3d_webgpu/src/webgpu_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Compiler with WgslModuleCompiler {
  final List<String> compiled = <String>[];

  @override
  Object compileModule(String name, String wgsl) {
    compiled.add(wgsl);
    return Object();
  }
}

const String _blur = '''
compute Blur {
  workgroup 8, 8;
  buffer weights: f32[] read;
  texture source: rgba8;
  image target: rgba8;
  kernel {
    let x = i32(id.x);
    let y = i32(id.y);
    store(target, x, y, load(source, x, y) * weights[0]);
  }
}
''';

void main() {
  test('a kernel bundle loads with no WGSL section of its own', () {
    // Mutation: demand the webgpu section, and a bundle of kernels is
    // refused by the one backend whose compute runs them natively.
    final compiler = _Compiler();
    final library = WebGpuLoadedShaderLibrary.load(
      compiler,
      kernelBundle('kernels', ComputeKernel.parseAll(_blur)).encode(),
    );
    final handle = library['Blur']!;
    final shader = handle.backend as WebGpuComputeShader;
    expect(shader.stage.workgroupSize, (8, 8, 1));
    expect(
      compiler.compiled.single,
      contains('@compute @workgroup_size(8, 8, 1)'),
    );
  });

  test('every binding is reflected in group zero, in declaration order', () {
    // Mutation: give the texture a sampler slot, and the layout names a
    // binding the WGSL does not declare: the browser refuses the pipeline.
    final stage = webgpuKernelStage(ComputeKernel.parse(_blur));
    expect(stage.storage.single.name, 'weights');
    expect(stage.storage.single.binding, 0);
    expect(stage.storage.single.readOnly, isTrue);
    expect(stage.loadedTextures.single.name, 'source');
    expect(stage.loadedTextures.single.binding, 1);
    expect(stage.textures, isEmpty);
    expect(stage.storageTextures.single.binding, 2);
    expect(stage.storageTextures.single.format, TextureFormat.r8g8b8a8UNormInt);
    expect(stage.storageTextures.single.access, StorageTextureAccess.writeOnly);
  });

  test('a reload compiles a kernel in use from its new source', () {
    // Mutation: skip compute handles on a reload, and a pipeline made after
    // it still runs the old kernel.
    final compiler = _Compiler();
    final library = WebGpuLoadedShaderLibrary.load(
      compiler,
      kernelBundle('kernels', ComputeKernel.parseAll(_blur)).encode(),
    );
    final handle = library['Blur']!;
    library.refresh(
      kernelBundle(
        'kernels',
        ComputeKernel.parseAll(
          _blur.replaceAll('workgroup 8, 8', 'workgroup 4, 4'),
        ),
      ).encode(),
    );
    expect(library['Blur'], same(handle));
    expect((handle.backend as WebGpuComputeShader).stage.workgroupSize, (
      4,
      4,
      1,
    ));
    expect(
      () => library.refresh(
        kernelBundle('kernels', const <ComputeKernel>[]).encode(),
      ),
      throwsA(
        isA<ShaderBundleException>().having(
          (e) => e.reason,
          'reason',
          contains('kernel "Blur"'),
        ),
      ),
    );
  });
}
