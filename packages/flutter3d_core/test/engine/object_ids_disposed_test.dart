// A question about the next frame, asked of a renderer that is disposed
// before any frame answers it.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

void main() {
  test('a frame of ids never drawn fails with where it was let go', () async {
    // Mutation: complete the question with the error alone, and the caller
    // awaiting it gets an empty stack trace with nothing to follow.
    final renderer = Renderer.create(device: FakeBackend());
    final ids = renderer.captureObjectIds();
    renderer.dispose();
    final (error, stack) = await ids.then<(Object?, StackTrace?)>(
      (_) => (null, null),
      onError: (Object error, StackTrace stack) => (error, stack),
    );
    expect(error, isA<StateError>());
    expect(stack.toString(), contains('dispose'));
  });
}
