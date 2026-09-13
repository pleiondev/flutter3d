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
void registerBackendOpener(
  String name,
  BackendOpener open, {
  bool asFallback = false,
}) {
  final entry = (name: name, open: open);
  if (asFallback) {
    _fallbackOpener = entry;
  } else {
    _preferredOpeners.insert(0, entry);
  }
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
void registerDevicePresenter<T extends GraphicsDevice>(Object presenter) {
  _presenters[T] = presenter;
}

/// The presenter [registerDevicePresenter] stored for [device]'s own
/// runtime type, or null if nothing ever registered one.
Object? lookUpDevicePresenter(GraphicsDevice device) =>
    _presenters[device.runtimeType];
