/// How a build picks which [GraphicsDevice] to open, and how a caller finds
/// the thing that shows a frame from one — both as registries a backend adds
/// itself to, rather than a list this package or `flutter3d_app` would have
/// to already know every entry of.
///
/// **Opening a device names no framework**, so the whole of that registry —
/// types, storage, resolution — lives here, in the vocabulary every backend
/// already depends on. Every backend can register itself directly: there is
/// nothing for `flutter3d_app` to do on a backend's behalf.
///
/// **Showing a frame returns a Flutter `Widget`**, which this package must
/// not name — that is the one Flutter import mcp-01n removed. So only the
/// generic half lives here: registered and looked up by a device's runtime
/// [Type], holding whatever a caller registered as [Object] and casting
/// nothing. `flutter3d_app` (or a genuinely third-party assembly layer)
/// supplies the typed `FramePresenter` shape and the cast back to it, since
/// that is the one place a `Widget` is allowed to be named.
library;

import 'graphics_device.dart';

/// Opens a [GraphicsDevice] at [width] by [height], or throws.
typedef BackendOpener =
    Future<GraphicsDevice> Function({required int width, required int height});

final List<({String name, BackendOpener open})> _preferredOpeners =
    <({String name, BackendOpener open})>[];
({String name, BackendOpener open})? _fallbackOpener;

/// What [registerBackendOpener] hands back, so a registration can be taken
/// off again.
///
/// **It exists because a registry with no way out is a registry that leaks
/// across tests.** An application registers its backends once at startup and
/// never wants this. A test does: `very_good test` runs an entire package's
/// suite in one process, so a backend registered by one test file is still
/// registered for every file after it — and a fake that draws nothing,
/// registered to keep a widget test off the software rasteriser, silently
/// becomes the backend a later test's *picture* is drawn with. That is a
/// green test asserting on an empty frame, which is the worst kind.
///
/// Idempotent: calling [undo] twice removes one registration, not two, and
/// removing one that something else already replaced does nothing.
final class BackendRegistration {
  BackendRegistration._(this._entry, {required this.asFallback});

  final ({String name, BackendOpener open}) _entry;

  /// Whether this took the single fallback slot rather than joining the
  /// preferred list.
  final bool asFallback;

  /// What was in the fallback slot before, put back by [undo] — otherwise a
  /// test that registered a fallback would leave the build with none, which
  /// is the one state `openRegisteredDevice` cannot recover from.
  ({String name, BackendOpener open})? _displaced;

  var _undone = false;

  void undo() {
    if (_undone) return;
    _undone = true;
    if (asFallback) {
      // Only if nothing else has taken the slot since: putting back a stale
      // fallback over a newer one would be a second bug wearing the shape of
      // a cleanup.
      if (identical(_fallbackOpener, _entry)) _fallbackOpener = _displaced;
      return;
    }
    _preferredOpeners.removeWhere(
      (({String name, BackendOpener open}) e) => identical(e, _entry),
    );
  }
}

/// Registers [open] as a backend a caller of [openRegisteredDevice] may try,
/// named [name] for the console line printed if it refuses to start.
///
/// Tried before every backend already registered — last registered, first
/// tried — unless [asFallback] is set, in which case [open] becomes *the*
/// fallback: the one backend tried last, and the only one
/// [openRegisteredDevice] still tries if every preferred one refuses.
/// Registering a second fallback replaces the first rather than adding a
/// second-to-last option — there is only ever one, since a fallback's whole
/// promise is being the thing still standing when nothing else is.
/// Returns a [BackendRegistration] whose `undo()` takes it off again. An
/// application ignores it; a test keeps it and undoes it in a tear-down, so
/// the next file in the same process opens the backend it expected to.
BackendRegistration registerBackendOpener(
  String name,
  BackendOpener open, {
  bool asFallback = false,
}) {
  final entry = (name: name, open: open);
  final registration = BackendRegistration._(entry, asFallback: asFallback);
  if (asFallback) {
    registration._displaced = _fallbackOpener;
    _fallbackOpener = entry;
  } else {
    _preferredOpeners.insert(0, entry);
  }
  return registration;
}

/// Opens the first registered backend that starts, preferred backends
/// before the fallback, calling [onFallback] with a message once for every
/// refusal along the way.
///
/// Throws [StateError] naming every refusal if nothing starts — which only
/// happens when nothing ever registered a fallback, since a real fallback's
/// own promise is that it always starts.
Future<GraphicsDevice> openRegisteredDevice({
  required int width,
  required int height,
  void Function(String message)? onFallback,
}) async {
  final refusals = <String>[];
  for (final entry in _preferredOpeners) {
    try {
      return await entry.open(width: width, height: height);
    } catch (error) {
      refusals.add('${entry.name}: $error');
      onFallback?.call(
        '${entry.name} would not start ($error), trying the next backend',
      );
    }
  }
  final fallback = _fallbackOpener;
  if (fallback != null) {
    try {
      return await fallback.open(width: width, height: height);
    } catch (error) {
      refusals.add('${fallback.name}: $error');
    }
  }
  throw StateError(
    'openRegisteredDevice: no registered backend could be opened — '
    '${refusals.join('; ')}',
  );
}

final Map<Type, Object> _presenters = <Type, Object>{};

/// Registers [presenter] — a value only the caller knows the shape of — as
/// what shows a frame from a device of exactly type [T].
///
/// Generic over [Object] rather than a named function type, because the
/// shape a presenter actually has returns a Flutter `Widget`, and this
/// package is the one place that type must not be named. `flutter3d_app`'s
/// own `registerFramePresenter` is a thin, typed wrapper over this.
/// Returns a [BackendRegistration]-shaped undo for the same reason that one
/// exists: a presenter registered for a fake device type outlives the test
/// that wanted it, and the next test to open a device of that type gets a
/// widget from a suite that has already finished.
PresenterRegistration registerDevicePresenter<T extends GraphicsDevice>(
  Object presenter,
) {
  final previous = _presenters.containsKey(T) ? _presenters[T] : null;
  _presenters[T] = presenter;
  return PresenterRegistration._(T, presenter, previous);
}

/// What [registerDevicePresenter] hands back, so a registration can be taken
/// off again. See [BackendRegistration] for why a registry needs this.
final class PresenterRegistration {
  PresenterRegistration._(this._type, this._presenter, this._previous);

  final Type _type;
  final Object _presenter;
  final Object? _previous;
  var _undone = false;

  void undo() {
    if (_undone) return;
    _undone = true;
    // Only if nothing has replaced it since, the same guard the backend
    // registration keeps: a cleanup that overwrites a newer registration is
    // not a cleanup.
    if (!identical(_presenters[_type], _presenter)) return;
    if (_previous == null) {
      _presenters.remove(_type);
    } else {
      _presenters[_type] = _previous;
    }
  }
}

/// The presenter [registerDevicePresenter] stored for [device]'s own
/// runtime type, or null if nothing ever registered one.
Object? lookUpDevicePresenter(GraphicsDevice device) =>
    _presenters[device.runtimeType];
