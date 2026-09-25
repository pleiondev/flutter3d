/// A fragment stage that writes fewer colours than the pass has attachments.
///
///     flutter test --platform chrome test/draw_buffers_test.dart
///
/// The temporal pass draws into the colour and the velocity target together,
/// and the hashed splat's fragment stage writes only the colour. GL ES refuses
/// a draw that leaves an active draw buffer with no output behind it: Chrome
/// logs "Active draw buffers with missing fragment shader outputs", reports
/// `INVALID_OPERATION`, and draws nothing. `splat-stochastic` came back an
/// empty frame on WebGL2 for exactly this, under a budget wide enough to pass.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

const String _vertex = '''#version 300 es
layout(location = 0) in vec3 position;
void main() {
  gl_Position = vec4(position, 1.0);
}
''';

/// One output, at location zero, the shape of `SplatHashed`.
const String _one = '''#version 300 es
precision highp float;
// out vec4 in_a_comment; must not count
layout(location = 0) out vec4 frag_color;
void shade(out vec4 unused) { unused = vec4(0.0); }
void main() {
  frag_color = vec4(1.0, 0.0, 0.0, 1.0);
}
''';

/// Both outputs, the shape of every stage that writes the velocity too.
const String _two = '''#version 300 es
precision highp float;
layout(location = 0) out vec4 frag_color;
layout(location = 1) out vec4 frag_velocity;
void main() {
  frag_color = vec4(0.0, 0.0, 1.0, 1.0);
  frag_velocity = vec4(0.0, 1.0, 0.0, 1.0);
}
''';

/// A triangle that covers the whole target.
final Float32List _cover = Float32List.fromList(<double>[
  -1, -1, 0.5, //
  3, -1, 0.5,
  -1, 3, 0.5,
]);

final Uint16List _indices = Uint16List.fromList(<int>[0, 1, 2]);

const int _size = 4;

void main() {
  test('the outputs a fragment stage declares are read off its source', () {
    expect(fragmentOutputNames(_one), <String>{'frag_color'});
    expect(fragmentOutputNames(_two), <String>{'frag_color', 'frag_velocity'});
    expect(fragmentOutputNames(_vertex), isEmpty);
    // The engine's own: the hashed splat writes the colour alone, and a
    // G-buffer stage writes three.
    expect(
      fragmentOutputNames(engineShaders.fragment['SplatHashed']!),
      <String>{'frag_color'},
    );
    expect(
      engineShaders.fragment.values.map(fragmentOutputNames),
      everyElement(isNotEmpty),
      reason:
          'a fragment stage whose outputs cannot be read writes every '
          'attachment, which is the failure this guards against',
    );
  });

  test('a one-output stage in a two-attachment pass draws, and leaves the '
      'second attachment as it was', () async {
    // Mutation: leave both draw buffers active whatever the program writes.
    // The draw is rejected with INVALID_OPERATION and the first attachment
    // keeps its clear colour.
    final device = WebGlDevice.create(
      width: _size,
      height: _size,
      sources: const ShaderSources(
        <String, String>{'Cover': _vertex},
        <String, String>{'One': _one, 'Two': _two},
      ),
    );
    if (device == null) fail('no WebGL2 context in this browser');
    addTearDown(device.dispose);

    final vertex = device.shaders['Cover']!;
    final one = device.createPipeline(vertex, device.shaders['One']!);
    final two = device.createPipeline(vertex, device.shaders['Two']!);

    TextureHandle target() => device.createTexture(
      const RenderTargetSpec(
        width: _size,
        height: _size,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    ColorTarget cleared(TextureHandle texture) => ColorTarget(
      texture: texture,
      loadAction: LoadAction.clear,
      clearValue: Vector4(0.25, 0.25, 0.25, 1.0),
    );
    void drawWith(CommandEncoder pass, PipelineHandle pipeline) => pass
      ..bindPipeline(pipeline)
      ..setPrimitiveType(PrimitiveType.triangle)
      ..setCullMode(CullMode.none)
      ..bindVertexData(ByteData.sublistView(_cover), 3)
      ..bindIndexData(ByteData.sublistView(_indices), IndexType.int16, 3)
      ..draw();
    Future<List<int>> centre(TextureHandle texture) async {
      final pixels = (await device.readPixels(texture))!.buffer.asUint8List();
      final at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
      return pixels.sublist(at, at + 4);
    }

    final colour = target();
    final velocity = target();
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[cleared(colour), cleared(velocity)],
      ),
    );
    drawWith(pass, one);
    pass.submit();

    expect(device.debugDrainErrors('one output, two attachments'), isNull);
    expect(await centre(colour), <int>[255, 0, 0, 255]);
    expect(await centre(velocity), <int>[64, 64, 64, 255]);

    // And the full list back for a stage that writes both, in the same pass
    // after the one that did not: the second attachment must be drawn again.
    final colour2 = target();
    final velocity2 = target();
    final both = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[cleared(colour2), cleared(velocity2)],
      ),
    );
    drawWith(both, one);
    drawWith(both, two);
    both.submit();

    expect(device.debugDrainErrors('two outputs after one'), isNull);
    expect(await centre(colour2), <int>[0, 0, 255, 255]);
    expect(await centre(velocity2), <int>[0, 255, 0, 255]);
  });
}
