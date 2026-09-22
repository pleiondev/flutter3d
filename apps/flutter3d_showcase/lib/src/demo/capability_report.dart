/// What the device in front of the person can do, and what it declined.
///
/// **Asked of the device, never of its name.** There is no "backend" value to
/// switch on, and a badge that said "not on WebGL" would be wrong the day that
/// backend learns the feature. The `supports*` getters of `GraphicsDevice` say
/// what is true now, and `FrameResult` says, after a frame, what was asked for
/// and not done. The page reports both and lets the person read the reason.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';

/// The needs a device meets.
final class CapabilityReport {
  const CapabilityReport(this.met);

  /// A device that meets everything, for a test that is not about a backend.
  const CapabilityReport.all() : met = const <Need>{...Need.values};

  factory CapabilityReport.of(GraphicsDevice device) => CapabilityReport(<Need>{
    if (device.supportsWireframe) Need.wireframe,
    if (device.supportsCubeTextures) Need.cubeTextures,
    if (device.supportsMipmaps) Need.mipmaps,
    if (device.supportsRenderToMip) Need.renderToMip,
    if (device.supportsStencil) Need.stencil,
    if (device.supportsBlendColor) Need.blendColor,
    if (device.supportsOffscreenMsaa) Need.offscreenMsaa,
  });

  final Set<Need> met;

  /// What [needs] asks for that this device lacks.
  List<Need> missing(Set<Need> needs) => <Need>[
    for (final Need need in needs)
      if (!met.contains(need)) need,
  ];

  /// One sentence for the badge, or null when nothing is missing.
  String? sentenceFor(Set<Need> needs) {
    final List<Need> lacking = missing(needs);
    if (lacking.isEmpty) return null;
    return 'This device has no ${lacking.map((Need n) => n.label).join(', ')}, '
        'so part of this page will not show.';
  }
}

/// What a frame was asked to do and this device could not, one short phrase
/// each.
///
/// Read after the first frame: a device can meet every need and still refuse
/// something only the frame knows, such as more shadow casters than it has
/// slots for. **Only what the machine refused is reported.** A pass skipped
/// because its setting is off, or because nothing wanted its output, is a
/// decision about the frame and every page has a dozen of them; listing those
/// would bury the one line that says this device cannot do what the page shows.
List<String> declinedBy(FrameResult frame) => <String>[
  if (frame.wireframeDeclined) 'wireframe is not available on this device',
  if (frame.shadowsDenied > 0) '${frame.shadowsDenied} shadow(s) were denied',
  for (final skipped in frame.skipped)
    if (skipped.reason.name == 'unsupported')
      '${skipped.name} is not available on this device',
];
