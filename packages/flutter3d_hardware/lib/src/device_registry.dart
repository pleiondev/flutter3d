/// How an engine picks which [GraphicsDevice] to open, and how it finds the
/// thing that shows a frame from one — a registry a backend adds itself to,
/// rather than a list this package or `flutter3d_app` would have to already
/// know every entry of.
///
/// **One registry per engine, since 1.0** (principle A.4 of the API review:
/// no global mutable state). Before it the openers and presenters were
/// top-level lists every engine in the isolate shared, so two engines — two
/// plugin hosts, a test beside an application — could not choose backends
/// of their own, and a fake registered by one test leaked into the next.
/// Now an engine owns a [DeviceRegistry], a backend's `register…Backend`
/// adds itself to the one it is handed, and every addition is a
/// [Registration] that takes it out again.
///
/// **Opening a device names no framework**, so the whole of opening lives
/// here, in the vocabulary every backend already depends on. **Showing a
/// frame returns a Flutter `Widget`**, which this package must not name, so
/// only the generic half lives here: a presenter registered for a device
/// type and looked up by `device is T`, held as [Object] and cast by
/// `flutter3d_app`, the one place a `Widget` is allowed to be named.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Registration;

import 'device_exceptions.dart';
import 'graphics_device.dart';

/// Opens a [GraphicsDevice] at [width] by [height], or throws.
typedef BackendOpener =
    Future<GraphicsDevice> Function({required int width, required int height});

/// The backends one engine may open, in the order it tries them, and the
/// presenters that show their frames.
final class DeviceRegistry {
  /// An empty registry: no backend until one is added.
  DeviceRegistry();

  final List<({String name, BackendOpener open})> _preferred =
      <({String name, BackendOpener open})>[];
  final List<({String name, BackendOpener open})> _fallbacks =
      <({String name, BackendOpener open})>[];
  final List<({bool Function(GraphicsDevice) accepts, Object presenter})>
  _presenters = <({bool Function(GraphicsDevice) accepts, Object presenter})>[];

  /// The names of the backends [open] would try, in the order it tries them —
  /// for an application's diagnostics screen, or a test checking what it
  /// registered.
  List<String> get backendNames => List<String>.unmodifiable(<String>[
    for (final entry in _preferred.reversed) entry.name,
    if (_fallbacks.isNotEmpty) _fallbacks.last.name,
  ]);

  /// Adds [open] as a backend [this.open] may try, named [name] for the line
  /// printed if it refuses to start.
  ///
  /// Tried before every backend already added — last added, first tried —
  /// unless [asFallback] is set, in which case [open] becomes *the* fallback:
  /// the one backend tried last, and the only one still tried if every
  /// preferred one refuses. Adding a second fallback puts it in front of the
  /// first until its registration is cancelled; there is only ever one in
  /// use, since a fallback's whole promise is being the thing still standing
  /// when nothing else is.
  ///
  /// The [Registration] takes it out again: an application ignores it; a
  /// test cancels it in a tear-down.
  Registration addBackend(
    String name,
    BackendOpener open, {
    bool asFallback = false,
  }) {
    final entry = (name: name, open: open);
    final list = asFallback ? _fallbacks : _preferred;
    list.add(entry);
    return Registration(
      () => list.removeWhere(
        (({String name, BackendOpener open}) e) => identical(e, entry),
      ),
    );
  }

  /// Opens the first backend that starts: the preferred ones, newest first,
  /// then the fallback. [onFallback] is told each refusal before the next
  /// backend is tried.
  ///
  /// Throws a [DeviceUnavailableException] naming every refusal when none
  /// starts, its [DeviceUnavailableException.refusals] one line per backend
  /// tried. (It was a `StateError` before 1.0: a machine with no backend that
  /// will start is something a correct program meets, not a mistake in it.)
  Future<GraphicsDevice> open({
    required int width,
    required int height,
    void Function(String message)? onFallback,
  }) async {
    final refusals = <String>[];
    for (final entry in _preferred.reversed.toList()) {
      try {
        return await entry.open(width: width, height: height);
      } catch (error) {
        refusals.add('${entry.name}: $error');
        onFallback?.call(
          '${entry.name} would not start ($error), trying the next backend',
        );
      }
    }
    if (_fallbacks.isNotEmpty) {
      final fallback = _fallbacks.last;
      try {
        return await fallback.open(width: width, height: height);
      } catch (error) {
        refusals.add('${fallback.name}: $error');
      }
    }
    throw DeviceUnavailableException(
      'DeviceRegistry.open: no backend could be opened — '
      '${refusals.isEmpty ? 'none was added' : refusals.join('; ')}',
      refusals: List<String>.unmodifiable(refusals),
    );
  }

  /// Adds [presenter] as what shows a frame from a device that `is` a [T] —
  /// `flutter3d_app`'s `FramePresenter`, held here as an [Object]. The latest
  /// addition a device matches wins until its registration is cancelled.
  ///
  /// **Matched with `is`, not by exact runtime type, since 1.0**, so a
  /// presenter for a backend's device also shows a frame from a subclass of
  /// it, and a wrapper that extends the device it wraps is not left without
  /// one.
  Registration addPresenter<T extends GraphicsDevice>(Object presenter) {
    final entry = (
      accepts: (GraphicsDevice device) => device is T,
      presenter: presenter,
    );
    _presenters.add(entry);
    return Registration(() => _presenters.remove(entry));
  }

  /// What shows a frame from [device] — the latest presenter added for a
  /// type [device] is — or null when nothing was added for it (absent).
  Object? presenterFor(GraphicsDevice device) {
    for (final entry in _presenters.reversed) {
      if (entry.accepts(device)) return entry.presenter;
    }
    return null;
  }
}
