/// The status-line sentence a freshly opened project earns.
///
/// **Pulled out of `main.dart` for the reason `transform_dispatch.dart`
/// was.** The three places a file finishes opening — the file picker, the
/// import screen, and a recent-projects row — all build the same sentence
/// from the same four numbers, and that is arithmetic on strings, checkable
/// without a window.
library;

/// "1 object" and "2 objects", because a status line that says "1 objects"
/// reads as something a program wrote rather than as a sentence.
String countLabel(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

/// The sentence `_cubit.opened` shows for a project called [name] that took
/// [openedInMs] milliseconds to read: its name, how much came in, and how
/// long it took.
String describeOpened({
  required String name,
  required int objectCount,
  required int triangleCount,
  required int materialCount,
  required int openedInMs,
}) =>
    '$name: '
    '${countLabel(objectCount, 'object')}, '
    '${countLabel(triangleCount, 'triangle')}, '
    '${countLabel(materialCount, 'material')}, '
    'opened in $openedInMs ms';
