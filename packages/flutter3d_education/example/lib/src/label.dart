import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter3d/flutter3d.dart' show Rgba8Image;
import 'package:flutter_math_fork/flutter_math.dart';

import 'glassware.dart';

/// What a tube holds: its formula in TeX, a note for the label, the label's
/// band colour, and the colour of the solution itself.
typedef Solution = ({String tex, String note, Color band, Color color});

const Color _paper = Color(0xFFF7F3E8);
const Color _ink = Color(0xFF1B1B1F);

/// The label is an ordinary Flutter widget: a coloured band, the formula
/// typeset by flutter_math_fork, which renders TeX in pure Dart, and a note.
///
/// The note is set in KaTeX's own roman so the label needs no font beyond the
/// ones flutter_math_fork carries, which keeps the picture the same on every
/// machine that renders it.
class LabelCard extends StatelessWidget {
  const LabelCard(this.solution, {super.key});

  final Solution solution;

  /// The card has the label strip's own proportions, so it lands on the
  /// glass undistorted; 384 pixels high is enough for the formula to stay
  /// sharp at the size a tube is seen.
  static final Size size = Size((384 * labelAspect()).roundToDouble(), 384);

  @override
  Widget build(BuildContext context) => Container(
    width: size.width,
    height: size.height,
    color: _paper,
    child: Column(
      children: [
        Container(height: 52, color: solution.band),
        const Spacer(),
        Padding(
          // The card goes more than half way round the tube; the
          // formula keeps to the middle third, the part that faces front.
          padding: EdgeInsets.symmetric(horizontal: size.width / 3),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Math.tex(
              solution.tex,
              textStyle: const TextStyle(fontSize: 112, color: _ink),
            ),
          ),
        ),
        const Spacer(),
        Text(
          solution.note,
          style: const TextStyle(
            fontFamily: 'KaTeX_Main',
            package: 'flutter_math_fork',
            fontSize: 46,
            color: _ink,
          ),
        ),
        const SizedBox(height: 22),
      ],
    ),
  );
}

/// Reads [boundary]'s pixels as RGBA8, once it has been painted.
Future<Rgba8Image> capture(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage();
  final data = await image.toByteData();
  final pixels = Rgba8Image(
    width: image.width,
    height: image.height,
    // A view of exactly the image's bytes: in a browser the buffer behind
    // the ByteData can be larger than the picture.
    pixels: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  image.dispose();
  return pixels;
}

/// Draws every label in the app's own tree, out of sight, reads each one's
/// pixels back and then takes them all out again.
///
/// **Inside the tree, not beside it.** A label could be laid out in a render
/// tree of its own, but that needs a second view on the same window, and in a
/// browser that second view was drawn over the app's own frame. Painted here
/// they are ordinary widgets: off screen, ignored by the pointer, gone once
/// [onPrinted] has had every picture.
class LabelPrinter extends StatefulWidget {
  const LabelPrinter({
    required this.solutions,
    required this.onPrinted,
    super.key,
  });

  final List<Solution> solutions;

  /// Called once for each label, with its picture turned for the lathe.
  final void Function(int index, Rgba8Image image) onPrinted;

  @override
  State<LabelPrinter> createState() => _LabelPrinterState();
}

class _LabelPrinterState extends State<LabelPrinter> {
  late final List<GlobalKey> _keys = [
    for (final _ in widget.solutions) GlobalKey(),
  ];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _print());
  }

  Future<void> _print() async {
    for (var i = 0; i < _keys.length; i++) {
      final boundary =
          _keys[i].currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) continue;
      widget.onPrinted(i, forLathe(await capture(boundary)));
    }
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) => _done
      ? const SizedBox.shrink()
      : IgnorePointer(
          child: Transform.translate(
            offset: const Offset(-20000, 0),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _keys.length; i++)
                    RepaintBoundary(
                      key: _keys[i],
                      child: LabelCard(widget.solutions[i]),
                    ),
                ],
              ),
            ),
          ),
        );
}

/// [image] turned half round, ready to go on a [labelBand].
///
/// v runs up the band from its bottom while a picture's rows run down, and u
/// runs with the angle, which seen from in front of the tube is right to
/// left. Reversing the order of the pixels fixes both at once; without it
/// the text comes out mirrored and upside down.
Rgba8Image forLathe(Rgba8Image image) {
  // Copied first, so the pixels start on a word of their own whatever view
  // they arrived in.
  final words = Uint8List.fromList(image.pixels).buffer.asUint32List();
  final turned = Uint32List.fromList(words.reversed.toList());
  return Rgba8Image(
    width: image.width,
    height: image.height,
    pixels: Uint8List.view(turned.buffer),
  );
}
