import 'package:flutter3d_editor/src/play/attach_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a published https editor warns of the permission prompt', () {
    // Mutation: the scheme check dropped, or the loopback hosts not excused.
    expect(
      attachNote(Uri.parse('https://editor.flutter3d.dev/'), web: true),
      contains('allow this site'),
    );
    expect(attachNote(Uri.parse('https://localhost:8443/'), web: true), isNull);
    expect(attachNote(Uri.parse('http://example.com/'), web: true), isNull);
    expect(
      attachNote(Uri.parse('https://editor.flutter3d.dev/'), web: false),
      isNull,
    );
  });
}
