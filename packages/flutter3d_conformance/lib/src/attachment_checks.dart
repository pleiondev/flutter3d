/// `maxColorAttachments`, which is a promise about two different things —
/// `gfx-21n`.
///
/// **A capability that only refuses is a capability nobody can trust, and one
/// that only permits is worse.** The number a backend answers here carries two
/// obligations at once: a pass within the limit has to open and its second
/// attachment has to actually receive the shader's second output, and a pass
/// past the limit has to be refused rather than accepted. Neither half implies
/// the other, and both fail silently — a dropped second output is a picture
/// that looks right with a buffer full of nothing behind it, and an accepted
/// over-long pass is, on one backend, a process that stops.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../flutter3d_conformance.dart';

/// The second colour attachment receives its own output, and one attachment
/// past the limit is refused.
///
/// **Why it draws rather than only asking.** `maxColorAttachments` is a number
/// a backend states, and stating two while dropping the second output is
/// exactly the failure the engine's surface buffer would show as a reflection
/// marching through geometry that is not there. So the check binds the probe
/// stage, which writes a different constant to each output, and reads both
/// back: equal targets mean the second attachment received a copy of the first
/// rather than its own colour, which is the shape of a backend that accepted
/// the attachment and wired one output to both.
///
/// **And why it then asks for one too many.** A limit that is never enforced
/// is a comment. The engine relies on the refusal — `gfx-50n`'s whole argument
/// is that on Impeller's OpenGL ES path the alternative to a throw is an
/// `FML_CHECK` — so a backend that quietly accepted an over-long pass would
/// leave the engine's gate resting on nothing.
///
/// A backend that answers one [decline]s the first half and is still held to
/// the second: it is the case the refusal exists for, so it is the last place
/// the refusal should go unchecked.
Future<void> checkColorAttachmentLimitIsHonoured(GraphicsDevice device) async {
  const size = 4;
  final limit = device.maxColorAttachments;
  require(
    limit >= 1,
    'answers $limit to maxColorAttachments, and a device that cannot open a '
    'single colour attachment cannot draw anything at all',
  );

  TextureHandle target() => device.createTexture(
    RenderTargetSpec(
      width: size,
      height: size,
      format: device.defaultColorFormat,
    ),
  );

  // The second half first, because every backend runs it: one attachment more
  // than the device says it has, refused rather than opened.
  final overLong = <ColorTarget>[
    for (var i = 0; i <= limit; i++) ColorTarget(texture: target()),
  ];
  var refused = false;
  try {
    device.beginRenderPass(RenderPassDescriptor(colors: overLong));
  } on Object {
    refused = true;
  }
  require(
    refused,
    'answers $limit to maxColorAttachments and opened a pass with '
    '${limit + 1} of them. The number is what the engine gates on, so a '
    'backend that does not enforce it turns the gate into a comment',
  );

  if (limit < 2) {
    decline(
      device,
      'answers $limit to maxColorAttachments, so there is no second '
      'attachment here to receive a second output. It was still held to '
      'refusing a pass that asks for one, which is the half of this check '
      'that matters most on a device that says no.',
    );
  }

  final probe = device.shaders['MrtProbe'];
  final vertex = device.shaders['FullscreenVertex'];
  require(
    probe != null && vertex != null,
    'the MRT probe stages are missing, so the second output cannot be drawn',
  );

  final first = target();
  final second = target();
  final pass = device.beginRenderPass(
    RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(texture: first, clearValue: Vector4.zero()),
        ColorTarget(texture: second, clearValue: Vector4.zero()),
      ],
    ),
  );
  // The oversized triangle every full-screen pass in this engine draws, with
  // the uv every vertex carries — the probe stage reads neither, but the
  // vertex stage declares both and a backend binds what is declared.
  final triangle = Float32List.fromList(<double>[
    -1, -1, 0, 0, //
    3, -1, 2, 0,
    -1, 3, 0, 2,
  ]);
  final indices = Uint16List.fromList(<int>[0, 1, 2]);

  pass
    ..setPrimitiveType(PrimitiveType.triangle)
    ..setCullMode(CullMode.none)
    // One `PassState` describes one attachment's blending, so the second is a
    // second call — and a backend that ignored the index would configure the
    // wrong target, which is its own way of failing this.
    ..setBlend(null, attachment: 1)
    ..bindPipeline(device.createPipeline(vertex!, probe!))
    ..bindVertexData(ByteData.sublistView(triangle), 3)
    ..bindIndexData(ByteData.sublistView(indices), IndexType.int16, 3)
    ..draw();
  pass.submit();

  final a = await device.readPixels(first);
  final b = await device.readPixels(second);
  require(
    a != null && b != null,
    'could not read back the two attachments, so nothing here can be said '
    'about what they hold',
  );

  final red = a!.getUint8(0);
  final blue = b!.getUint8(2);
  final otherRed = b.getUint8(0);
  require(
    !(a.getUint8(0) == b.getUint8(0) && a.getUint8(2) == b.getUint8(2)),
    'answers $limit to maxColorAttachments and gave both attachments the '
    'same colour — attachment 0 red $red, attachment 1 red $otherRed blue '
    '$blue. The stage writes a different constant to each output, so equal '
    'targets mean the second output was not honoured and the second '
    'attachment received a copy of the first',
  );
}
