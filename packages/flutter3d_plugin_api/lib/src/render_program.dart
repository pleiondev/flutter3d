import 'dart:typed_data';

/// A program a run-time plugin brings that drives one of its render steps
/// frame by frame: what a Wasm render module is, as the renderer sees it.
///
/// **The renderer runs it; the runtime that loaded it says what it is.**
/// `flutter3d_plugin_runtime` decodes a `.f3dplugin`'s `wasmRender` module
/// and makes one of these for the render step it drives; the render step
/// section of `flutter3d_core` asks for it by the step's name
/// ([DataSectionContext.renderProgram]) and runs it before the step draws.
/// Neither package depends on the other: this is where they meet.
///
/// **Outside the simulation.** A program runs once a frame, in an instance
/// of its own, and nothing it keeps is part of a save or a digest: a frame
/// a client draws and a server never does cannot part the two.
///
/// Extendable outside this package, and stays so through 1.x: a member
/// added in a minor arrives with a body.
abstract base class RenderProgram {
  const RenderProgram();

  /// The parameters the program sets, by the index its commands name them
  /// with: names of uniforms of the step's stage.
  List<String> get parameters;

  /// Runs once for one view of one frame, before the step draws, issuing
  /// its commands into [frame]. The step draws that frame only if the
  /// program called [RenderProgramFrame.draw].
  ///
  /// Throws to stop: the renderer switches the step's node off with what it
  /// threw, as it does any node that throws, and names the plugin.
  void run(RenderProgramFrame frame);
}

/// What a [RenderProgram] is handed each frame: what the frame is, and the
/// commands that reach its step.
///
/// **Made by the renderer, reused frame to frame**, never kept by a
/// program past [RenderProgram.run]. One object that can gain members, a
/// command or a fact about the frame, without a program written against
/// 1.0 breaking.
abstract base class RenderProgramFrame {
  const RenderProgramFrame();

  /// The frame being drawn, counted by the renderer from nought.
  int get frame;

  /// The view being drawn, by its index in the frame.
  int get view;

  /// The frame's time, in seconds since the renderer began.
  double get time;

  /// The view's width, in pixels.
  int get width;

  /// The view's height, in pixels.
  int get height;

  /// The components [write] names of one of the program's parameters are
  /// its values from this frame's draw on, until they are set again; a
  /// parameter never set is the default its stage declares. The values are
  /// copied before this returns: the caller may reuse them at once.
  ///
  /// Throws a `PluginException` for a parameter the step's stage does not
  /// have, and for components past the ones it has.
  ///
  /// **Breaking in 1.0.0-rc.1:** one write object, where it took
  /// `(parameter, component, value)` and `setParameterFloats` took
  /// `(parameter, values)`; a write can gain members, a list of parameters
  /// cannot.
  void setParameter(RenderParameterWrite write);

  /// The step draws this frame, with its parameters as set.
  void draw();

  /// The code the light type called [name] (`acme.tube`) is packed with
  /// this frame, or null where no hook packs it.
  int? lightCode(String name) => null;
}

/// What a [RenderProgram] sets one of its parameters with
/// ([RenderProgramFrame.setParameter]): which parameter, from which
/// component, to which values.
///
/// **One object, so a command can grow** — a write that blends, say —
/// without a program written against 1.0 breaking.
final class RenderParameterWrite {
  /// Parameter [parameter]'s components from [component] on are [values]:
  /// the first [values].length of them when [component] is nought.
  RenderParameterWrite(this.parameter, this.values, {this.component = 0});

  /// Component [component] of parameter [parameter] is [value].
  RenderParameterWrite.component(this.parameter, this.component, double value)
    : values = Float32List(1)..[0] = value;

  /// The parameter, by its index in [RenderProgram.parameters].
  final int parameter;

  /// The first component written: nought for `x` or a scalar.
  final int component;

  /// The values written, from [component] on, in the stage's 32-bit
  /// floats. Read during the call it is handed to, never kept.
  final Float32List values;

  @override
  String toString() =>
      'RenderParameterWrite($parameter, from $component: $values)';
}
