import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe', () {
    final data = const SphereShape(radius: 1.0, segments: 12, rings: 6).build();
    // ignore: avoid_print
    print(
      'layout floats: ${data.layout.floatsPerVertex}, '
      'stride: ${data.layout.strideInBytes}, '
      'vertices: ${data.vertexCount}, '
      'bytes: ${data.vertexBytes.lengthInBytes}, '
      'bytes/vertex: ${data.vertexBytes.lengthInBytes / data.vertexCount}',
    );
    // ignore: avoid_print
    print(
      'standard stride: ${VertexLayout.standard.strideInBytes}, '
      'position at ${VertexLayout.standard.floatOffsetOf('position')}, '
      'normal at ${VertexLayout.standard.floatOffsetOf('normal')}',
    );
  });
}
