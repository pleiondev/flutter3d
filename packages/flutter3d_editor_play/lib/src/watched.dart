import 'dart:async';

/// A value and the news of it changing, with no Flutter in it.
///
/// What `ValueNotifier` was to Play inside the editor application: a panel
/// rebuilds from [changes], a server reads [value] when it is asked.
final class Watched<T> {
  Watched(this._value);

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast();

  T get value => _value;
  set value(T next) {
    _value = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  /// Every value set from now on.
  Stream<T> get changes => _changes.stream;

  Future<void> close() => _changes.close();
}
