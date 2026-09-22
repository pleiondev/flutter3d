import 'package:flutter3d_showcase/src/docs/dart_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String code = '''
// a comment
@override
final Vector3 v = Vector3(1.5, 0x10, "s");
''';

  test('the tokens joined give the source back exactly', () {
    // Mutation: drop the text between two matches. The Source tab would then
    // show a file that is not the one that runs.
    expect(tokenizeDart(code).map((Token t) => t.text).join(), code);
  });

  test('names the kinds a reader looks for', () {
    final Map<String, TokenKind> kinds = <String, TokenKind>{
      for (final Token t in tokenizeDart(code)) t.text: t.kind,
    };
    expect(kinds['// a comment'], TokenKind.comment);
    expect(kinds['@override'], TokenKind.annotation);
    expect(kinds['final'], TokenKind.keyword);
    expect(kinds['Vector3'], TokenKind.type);
    expect(kinds['1.5'], TokenKind.number);
    expect(kinds['0x10'], TokenKind.number);
    expect(kinds['"s"'], TokenKind.string);
  });

  test('a line it cannot read comes out as plain text', () {
    expect(tokenizeDart('%%% ###').single.kind, TokenKind.plain);
  });
}
