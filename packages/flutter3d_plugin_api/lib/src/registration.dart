import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show PluginException, Registration;

import 'manifest.dart';

/// Thrown when something is registered under a name another registration
/// already has: a second render step called `acme.glow`, a node, a phase,
/// a system, a plugin id.
///
/// **A [PluginException], so a plugin's install catches one kind of
/// refusal.** A name taken is data a correct program can be handed — two
/// plugins that both thought of `glow` — and is refused the way a name
/// outside the namespace is, never as an `ArgumentError`, which is a bug in
/// the caller. [name] is the name, [what] the kind of thing (`the render
/// step`), and [owner] who has it, as a person reads it (`plugin
/// "acme.bloom"`, `the application`), or null where the registry does not
/// know.
final class NameTakenException extends PluginException {
  /// [name], as [what], is taken, by [owner] when known; [detail] says
  /// more, in a sentence that follows the first.
  NameTakenException(
    this.name, {
    required this.what,
    this.owner,
    String? detail,
  }) : super(
         '$what "$name" is already '
         '${owner == null ? 'registered' : 'registered, by $owner'}'
         '${detail == null ? '' : '; $detail'}',
       );

  /// The name asked for.
  final String name;

  /// What it names: `the render step`, `the node`, `the system`.
  final String what;

  /// Who has it, or null where the registry does not know.
  final String? owner;

  @override
  String toString() => 'NameTakenException: $message';
}

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

  /// The registries that come with this one, found by `PluginHost.registry`
  /// as if each had been handed to the host itself.
  ///
  /// How one handle brings a subsystem's several registries: a renderer's
  /// render steps bring its lighting models, its light types and its
  /// draw-list hooks, so an engine that hands the host
  /// `renderer.renderSteps` gives a plugin all of them. None by default.
  Iterable<PluginRegistry> get companions => const <PluginRegistry>[];
}
