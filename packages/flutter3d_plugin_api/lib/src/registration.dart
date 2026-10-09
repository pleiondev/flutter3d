import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Registration;

import 'manifest.dart';

/// The plugin on whose behalf a registry is being called.
///
/// Handed to [PluginRegistry.forPlugin], which returns a view of the
/// registry that files everything under this scope. A registry uses three
/// things from it:
///
/// * [manifest], to hold the plugin to what it declared — a view plugin
///   adding a step system is refused here;
/// * [rank], the plugin's place in the install order, which breaks ties
///   between registrations no constraint orders — read when the registry
///   sorts, not when it registers, since a reorder changes it;
/// * [track], to hand the host each [Registration] so disabling the plugin
///   cancels it.
///
/// Made by the plugin host, never by a plugin.
abstract base class PluginScope {
  const PluginScope();

  PluginManifest get manifest;

  /// The plugin's position in the install order, from 0. Registrations made
  /// outside any plugin — by the application itself — rank as -1 and so
  /// come first among ties.
  int get rank;

  void track(Registration registration);
}

/// Something the engine owns and plugins add to: loop phases, event
/// subscriptions, render steps, decoders.
///
/// **Extended by the engine, called by plugins.** `base`, so nobody
/// implements it from outside, and a member added in a later minor of the
/// plugin API arrives with a default and breaks no extender.
///
/// Each registry belongs to one engine instance. Nothing here is global:
/// two engines in one process — an editor and the game it plays — have two
/// sets of registries and their plugins do not meet. What a registry holds
/// is keyed by a stable name — a phase's, a system's, an event's, a
/// plugin's id — and never by a runtime type, which is minified on the web.
abstract base class PluginRegistry {
  const PluginRegistry();

  /// This registry as [scope]'s plugin sees it: everything registered
  /// through the result is tracked by [scope], ranked by it, and checked
  /// against its manifest. Must return the same type the registry is looked
  /// up by.
  PluginRegistry forPlugin(PluginScope scope);
}
