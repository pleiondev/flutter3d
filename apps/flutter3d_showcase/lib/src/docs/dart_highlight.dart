/// Colouring Dart source, without a library.
///
/// **A tokenizer and nothing else.** It reads comments, strings, numbers,
/// annotations, keywords and type names, which is what tells a reader where
/// they are in a page of scene code. It does not parse: a line it cannot read
/// comes out as plain text, never as an error, because the Source tab must
/// always show the file. The site colours the same files with highlight.js;
/// this is for the app, which has no HTML to hand it to.
///
/// No Flutter import: the widget that turns tokens into spans is in
/// `source_view.dart`.
library;

enum TokenKind { comment, string, number, keyword, type, annotation, plain }

final class Token {
  const Token(this.kind, this.text);

  final TokenKind kind;
  final String text;
}

const Set<String> _keywords = <String>{
  'abstract',
  'as',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'override',
  'part',
  'required',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

final RegExp _tokenPattern = RegExp(
  r'(//[^\n]*)' // comment
  r"|('''[\s\S]*?'''" // strings, longest form first
  r'|"""[\s\S]*?"""'
  r"|'(?:\\.|[^'\\\n])*'"
  r'|"(?:\\.|[^"\\\n])*")'
  r'|(@\w+)' // annotation
  r'|(\b0x[0-9a-fA-F]+\b|\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b)' // number
  r'|(\b[A-Za-z_]\w*\b)', // word
);

/// [source] as a run of tokens that, joined, give [source] back exactly.
List<Token> tokenizeDart(String source) {
  final List<Token> out = <Token>[];
  var at = 0;
  for (final RegExpMatch match in _tokenPattern.allMatches(source)) {
    if (match.start > at) {
      out.add(Token(TokenKind.plain, source.substring(at, match.start)));
    }
    final String text = match.group(0)!;
    final TokenKind kind;
    if (match.group(1) != null) {
      kind = TokenKind.comment;
    } else if (match.group(2) != null) {
      kind = TokenKind.string;
    } else if (match.group(3) != null) {
      kind = TokenKind.annotation;
    } else if (match.group(4) != null) {
      kind = TokenKind.number;
    } else if (_keywords.contains(text)) {
      kind = TokenKind.keyword;
    } else if (text.isNotEmpty &&
        text[0] == text[0].toUpperCase() &&
        text[0] != '_' &&
        RegExp('[a-z]').hasMatch(text)) {
      kind = TokenKind.type;
    } else {
      kind = TokenKind.plain;
    }
    out.add(Token(kind, text));
    at = match.end;
  }
  if (at < source.length) {
    out.add(Token(TokenKind.plain, source.substring(at)));
  }
  return out;
}
