import 'dart:async';

/// A value and the news of it changing, with no Flutter in it.
///
/// What `ValueNotifier` was to Play inside the editor application: a panel
/// rebuilds from [changes], a server reads [value] when it is asked.
final class Watched<T> {
  /// A value starting at the one given, with no change announced for it.
  Watched(this._value);

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast();

  /// The value now. Setting it announces the new one on [changes], even
  /// when it equals the old, unless [close] has run.
  T get value => _value;
  set value(T next) {
    _value = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  /// Every value set from now on.
  Stream<T> get changes => _changes.stream;

  /// Ends [changes]; [value] can still be read and set, silently.
  Future<void> close() => _changes.close();
}
