/// The three pages this service renders — plain string HTML, not a
/// component library.
///
/// **No jaspr here.** `cloud/server` renders with it because its pages carry
/// forms, sessions and a signed-in/out nav — real reactivity a component
/// tree earns its keep for. Nothing here has a form or a viewer identity:
/// a lesson page is the same bytes for everyone who opens it, so a
/// string-returning function is the honest amount of machinery, not a
/// corner cut.
library;

import 'dart:convert';

import '../lessons_registry.dart';

const _htmlEscape = HtmlEscape();

/// The public page at `/l/<slug>`: title, description, the lesson itself in
/// an iframe, and the embed snippet for a third-party page to copy.
String lessonPage(Lesson lesson, {required String baseUrl}) {
  final title = _htmlEscape.convert(lesson.title);
  final description = _htmlEscape.convert(lesson.description);
  final embedSrc = '$baseUrl/e/${lesson.slug}';
  return '''
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title — flutter3d lessons</title>
<style>
  body { font: 16px/1.5 system-ui, sans-serif; max-width: 860px; margin: 2rem auto; padding: 0 1rem; color: #1a1a1a; }
  iframe { width: 100%; height: 70vh; border: 0; display: block; background: #111; }
  code { background: #f0f0f0; padding: 0.15em 0.4em; border-radius: 3px; }
</style>
</head>
<body>
<h1>$title</h1>
<p>$description</p>
${_iframe(assetSrc(lesson))}
<p>Встроить на своей странице:</p>
<pre><code>&lt;iframe src="$embedSrc" style="width:100%;height:70vh;border:0" allow="fullscreen"&gt;&lt;/iframe&gt;</code></pre>
</body>
</html>
''';
}

/// The bare page at `/e/<slug>`: nothing but the iframe, full-screen — this
/// is the address a third-party page's own `<iframe src="...">` names, so it
/// carries no chrome of its own to nest inside someone else's.
String embedPage(Lesson lesson) {
  final title = _htmlEscape.convert(lesson.title);
  return '''
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
  html, body { margin: 0; height: 100%; background: #111; }
  iframe { width: 100%; height: 100%; border: 0; display: block; }
</style>
</head>
<body>
${_iframe(assetSrc(lesson))}
</body>
</html>
''';
}

/// The bare domain (`/`) and any other address this service does not
/// answer — found the hard way: without this, the bare domain fell through
/// to [lessonNotFoundPage] and told a visitor who had typed no slug at all
/// that "the lesson" was not found, which is true of nothing they asked for.
String homePage() {
  final items = lessons
      .map(
        (lesson) =>
            '<li><a href="/l/${lesson.slug}">${_htmlEscape.convert(lesson.title)}</a> — '
            '${_htmlEscape.convert(lesson.description)}</li>',
      )
      .join('\n');
  return '''
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>flutter3d lessons</title>
<style>
  body { font: 16px/1.5 system-ui, sans-serif; max-width: 860px; margin: 2rem auto; padding: 0 1rem; color: #1a1a1a; }
  li { margin: 0.5em 0; }
</style>
</head>
<body>
<h1>flutter3d lessons</h1>
<ul>
$items
</ul>
</body>
</html>
''';
}

/// A slug that names no [Lesson] in the registry.
String lessonNotFoundPage() => '''
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Урок не найден — flutter3d lessons</title>
</head>
<body>
<h1>Урок не найден</h1>
<p>Такого урока нет.</p>
</body>
</html>
''';

/// Any address this service has no route for at all — distinct from
/// [lessonNotFoundPage], which is specifically "that slug is not a lesson".
String notFoundPage() => '''
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Страница не найдена — flutter3d lessons</title>
</head>
<body>
<h1>Страница не найдена</h1>
<p><a href="/">Список уроков</a></p>
</body>
</html>
''';

/// The viewer build's own address for [lesson] — `/app/?level=<asset>`, the
/// same query-parameter door `flutter3d_modeler` opens for `?model=`.
String assetSrc(Lesson lesson) =>
    '/app/?level=${Uri.encodeQueryComponent(lesson.levelAsset)}';

String _iframe(String src) =>
    '<iframe src="$src" allow="fullscreen" allowfullscreen loading="lazy"></iframe>';
