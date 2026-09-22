/// The lessons this service can show — in code, not a database or a file on
/// disk.
///
/// **Honest about what exists today.** `prep-00`/`prep-01`/`prep-02`
/// (`doc/lesson-scenarios-plan.md`) — picking a real object to tear down,
/// writing real lesson text — have not happened. What this registry names
/// today is the one document that already round-trips end to end:
/// `apps/flutter3d_lesson_viewer/assets/levels/tour.json`, the same
/// three-step camera tour `tpl-04`'s `viewer.json` proved. A second lesson,
/// or a hundred, is another [Lesson] in this list — this is not a
/// placeholder for a registry that reads a database; nobody has asked for
/// uploaded, per-user lessons yet, and a person's own accounts and storage
/// are what `cloud/server` already is for a different kind of file.
library;

/// One lesson: a slug for its URL, a title and description for its page, and
/// the level asset the viewer build should open.
final class Lesson {
  const Lesson({
    required this.slug,
    required this.title,
    required this.description,
    required this.levelAsset,
  });

  /// The path segment in `/l/<slug>` and `/e/<slug>`.
  final String slug;

  final String title;
  final String description;

  /// A path bundled into `flutter3d_lesson_viewer`'s web build, read by its
  /// own `?level=` query parameter (`apps/flutter3d_lesson_viewer/lib/main.dart`).
  final String levelAsset;
}

const lessons = <Lesson>[
  Lesson(
    slug: 'engine-tour',
    title: 'Тур по сцене',
    description:
        'Три вида камеры вокруг одной сцены и вопрос с проверкой в конце — '
        'первый интерактивный урок, проигрываемый в браузере без авторинга.',
    levelAsset: 'assets/levels/tour.json',
  ),
  // `ls-e-04`'s own second half: the same shared content `ls-i-03` already
  // closed (`apps/flutter3d_lesson_viewer/assets/levels/housing.json`),
  // reachable through this registry rather than through new code — `/e/
  // control-box` is this row's own "embeds into a test internal page
  // through an iframe with no code" acceptance, literally, since the route
  // itself already carries no framing header for any slug named here.
  Lesson(
    slug: 'control-box',
    title: 'Замена батареи в блоке управления',
    description:
        'Семь шагов разборки и сборки блока управления — от корпуса до '
        'батареи и обратно, на планшете техника без сети.',
    levelAsset: 'assets/levels/housing.json',
  ),
];

/// The lesson named [slug], or null when nothing in [lessons] answers to it.
Lesson? lessonBySlug(String slug) {
  for (final lesson in lessons) {
    if (lesson.slug == slug) return lesson;
  }
  return null;
}
