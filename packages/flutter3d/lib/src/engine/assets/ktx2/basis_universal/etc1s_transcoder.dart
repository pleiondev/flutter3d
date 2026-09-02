/// ETC1S → RGBA8: the codebook and per-block bitstream Basis Universal packs
/// into a KTX2 file's supercompression global data plus its one "level".
///
/// Ported line-for-line from `basisu_lowlevel_etc1s_transcoder::decode_palettes`,
/// `::decode_tables` and `::transcode_slice` (the `block_format::cRGBA32`
/// branch) in `KhronosGroup/KTX-Software`'s
/// `external/basis_universal/transcoder/basisu_transcoder.cpp`. Verified
/// against real encoded files, not against this port's own understanding of
/// the format — see `flutter3d_samples/doc/ktx2_fixtures.md`.
///
/// **What this reads.** One image, one level: a codebook of shared ETC1
/// endpoints (a 555 colour plus a 3-bit intensity-table index — despite the
/// field being called `inten5`, `decode_palettes` masks it to 3 bits, so the
/// name is the format's, not a hint about its range) and a codebook of
/// shared selectors (sixteen 2-bit per-pixel picks into that endpoint's four
/// intensity-adjusted colours), then a bitstream that assigns each 4x4 block
/// one codebook entry of each kind. Global codebooks (files that reference
/// another file's palette) and video (inter-frame prediction) are refused by
/// [Ktx2Texture] before this is reached.
library;

import 'dart:typed_data';

import '../ktx2_format.dart';
import 'bitwise_decoder.dart';

/// One entry of the shared endpoint codebook: a 5-bit-per-channel colour and
/// a 3-bit ETC1 intensity-table index.
final class _Endpoint {
  _Endpoint(this.r5, this.g5, this.b5, this.intenTable);

  int r5, g5, b5;
  int intenTable;
}

/// One entry of the shared selector codebook: which of an endpoint's four
/// intensity-adjusted colours each of the 16 pixels in a block picks.
///
/// [rows] holds one packed byte per pixel row, 2 bits per column — the same
/// layout `decode_palettes` reads the codebook in and `transcode_slice`
/// reads a block's pixels from, so no unpacking into a flatter shape earns
/// anything.
final class _Selector {
  _Selector(this.rows);

  final Uint8List rows; // length 4, one byte per row y, 2 bits per column x.

  int at(int x, int y) => (rows[y] >> (x * 2)) & 3;
}

/// The four possible colours the endpoint at [index] contributes to a block,
/// selector value 0..3 straight into the result.
List<int> _blockColors(List<_Endpoint> endpoints, int index) {
  final e = endpoints[index];
  // 5-bit to 8-bit: bit replication, `(v << 3) | (v >> 2)`.
  final r = (e.r5 << 3) | (e.r5 >> 2);
  final g = (e.g5 << 3) | (e.g5 >> 2);
  final b = (e.b5 << 3) | (e.b5 >> 2);
  final delta = _etc1IntensityTables[e.intenTable];
  return [
    _packRgb(r, g, b, delta[0]),
    _packRgb(r, g, b, delta[1]),
    _packRgb(r, g, b, delta[2]),
    _packRgb(r, g, b, delta[3]),
  ];
}

int _clamp255(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

int _packRgb(int r, int g, int b, int delta) {
  final rr = _clamp255(r + delta);
  final gg = _clamp255(g + delta);
  final bb = _clamp255(b + delta);
  return rr | (gg << 8) | (bb << 16) | (0xFF << 24);
}

/// The standard ETC1 intensity modifier table, `g_etc1_inten_tables` in the
/// reference — eight rows, one per 3-bit intensity index, four columns, one
/// per 2-bit selector value.
const List<List<int>> _etc1IntensityTables = [
  [-8, -2, 2, 8],
  [-17, -5, 5, 17],
  [-29, -9, 9, 29],
  [-42, -13, 13, 42],
  [-60, -18, 18, 60],
  [-80, -24, 24, 80],
  [-106, -33, 33, 106],
  [-183, -47, 47, 183],
];

const int _colorPal0PrevHi = 9;
const int _colorPal1PrevHi = 21;

/// Decodes the endpoint and selector codebooks from a Basis supercompression
/// global data section's `endpointsData` and `selectorsData`.
final class _Palettes {
  _Palettes(this.endpoints, this.selectors);

  final List<_Endpoint> endpoints;
  final List<_Selector> selectors;

  factory _Palettes.decode(
    Uint8List endpointsData,
    int numEndpoints,
    Uint8List selectorsData,
    int numSelectors,
  ) {
    final endpointCodec = BitwiseDecoder(endpointsData);
    final color5DeltaModel0 = HuffmanDecodingTable();
    final color5DeltaModel1 = HuffmanDecodingTable();
    final color5DeltaModel2 = HuffmanDecodingTable();
    final intenDeltaModel = HuffmanDecodingTable();
    endpointCodec.readHuffmanTable(color5DeltaModel0);
    endpointCodec.readHuffmanTable(color5DeltaModel1);
    endpointCodec.readHuffmanTable(color5DeltaModel2);
    endpointCodec.readHuffmanTable(intenDeltaModel);
    if (!color5DeltaModel0.isValid ||
        !color5DeltaModel1.isValid ||
        !color5DeltaModel2.isValid ||
        !intenDeltaModel.isValid) {
      throw const Ktx2FormatException(
        'ETC1S endpoint codebook: a required Huffman table is empty.',
      );
    }

    final endpointsAreGrayscale = endpointCodec.getBits(1) != 0;

    final endpoints = <_Endpoint>[];
    var prevR5 = 16, prevG5 = 16, prevB5 = 16;
    var prevInten = 0;
    for (var i = 0; i < numEndpoints; i++) {
      final intenDelta = endpointCodec.decodeHuffman(intenDeltaModel);
      final inten = (intenDelta + prevInten) & 7;
      prevInten = inten;

      final channels = endpointsAreGrayscale ? 1 : 3;
      final prev = [prevR5, prevG5, prevB5];
      final decoded = [prevR5, prevG5, prevB5];
      for (var c = 0; c < channels; c++) {
        final HuffmanDecodingTable model;
        if (prev[c] <= _colorPal0PrevHi) {
          model = color5DeltaModel0;
        } else if (prev[c] <= _colorPal1PrevHi) {
          model = color5DeltaModel1;
        } else {
          model = color5DeltaModel2;
        }
        final delta = endpointCodec.decodeHuffman(model);
        final v = (prev[c] + delta) & 31;
        decoded[c] = v;
        prev[c] = v;
      }
      prevR5 = prev[0];
      prevG5 = prev[1];
      prevB5 = prev[2];
      final r = decoded[0];
      final g = endpointsAreGrayscale ? decoded[0] : decoded[1];
      final b = endpointsAreGrayscale ? decoded[0] : decoded[2];
      endpoints.add(_Endpoint(r, g, b, inten));
    }

    final selectorCodec = BitwiseDecoder(selectorsData);
    final usedGlobalSelectorCodebook = selectorCodec.getBits(1) == 1;
    if (usedGlobalSelectorCodebook) {
      throw const Ktx2FormatException(
        'ETC1S: global selector codebooks are not supported yet.',
      );
    }
    final usedHybridSelectorCodebook = selectorCodec.getBits(1) == 1;
    if (usedHybridSelectorCodebook) {
      throw const Ktx2FormatException(
        'ETC1S: hybrid global selector codebooks are not supported yet.',
      );
    }
    final usedRawEncoding = selectorCodec.getBits(1) == 1;

    final selectors = <_Selector>[];
    if (usedRawEncoding) {
      for (var i = 0; i < numSelectors; i++) {
        final rows = Uint8List(4);
        for (var j = 0; j < 4; j++) {
          rows[j] = selectorCodec.getBits(8);
        }
        selectors.add(_Selector(rows));
      }
    } else {
      final deltaSelectorPalModel = HuffmanDecodingTable();
      selectorCodec.readHuffmanTable(deltaSelectorPalModel);
      if (numSelectors > 1 && !deltaSelectorPalModel.isValid) {
        throw const Ktx2FormatException(
          'ETC1S selector codebook: the delta table is empty for more than '
          'one selector.',
        );
      }
      final prevBytes = Uint8List(4);
      for (var i = 0; i < numSelectors; i++) {
        final rows = Uint8List(4);
        if (i == 0) {
          for (var j = 0; j < 4; j++) {
            final b = selectorCodec.getBits(8);
            prevBytes[j] = b;
            rows[j] = b;
          }
        } else {
          for (var j = 0; j < 4; j++) {
            final deltaByte = selectorCodec.decodeHuffman(
              deltaSelectorPalModel,
            );
            final b = deltaByte ^ prevBytes[j];
            prevBytes[j] = b;
            rows[j] = b;
          }
        }
        selectors.add(_Selector(rows));
      }
    }

    return _Palettes(endpoints, selectors);
  }
}

/// The four Huffman models a slice's per-block bitstream is coded against,
/// plus the selector history buffer size — everything `tablesData` holds.
final class _Tables {
  _Tables(
    this.endpointPredModel,
    this.deltaEndpointModel,
    this.selectorModel,
    this.selectorHistoryBufRleModel,
    this.selectorHistoryBufSize,
  );

  final HuffmanDecodingTable endpointPredModel;
  final HuffmanDecodingTable deltaEndpointModel;
  final HuffmanDecodingTable selectorModel;
  final HuffmanDecodingTable selectorHistoryBufRleModel;
  final int selectorHistoryBufSize;

  factory _Tables.decode(Uint8List tableData) {
    final codec = BitwiseDecoder(tableData);
    final endpointPredModel = HuffmanDecodingTable();
    final deltaEndpointModel = HuffmanDecodingTable();
    final selectorModel = HuffmanDecodingTable();
    final selectorHistoryBufRleModel = HuffmanDecodingTable();
    codec.readHuffmanTable(endpointPredModel);
    if (!endpointPredModel.isValid) {
      throw const Ktx2FormatException(
        'ETC1S tables: endpoint predictor model is empty.',
      );
    }
    codec.readHuffmanTable(deltaEndpointModel);
    if (!deltaEndpointModel.isValid) {
      throw const Ktx2FormatException(
        'ETC1S tables: delta endpoint model is empty.',
      );
    }
    codec.readHuffmanTable(selectorModel);
    if (!selectorModel.isValid) {
      throw const Ktx2FormatException('ETC1S tables: selector model is empty.');
    }
    codec.readHuffmanTable(selectorHistoryBufRleModel);
    if (!selectorHistoryBufRleModel.isValid) {
      throw const Ktx2FormatException(
        'ETC1S tables: selector history RLE model is empty.',
      );
    }
    final selectorHistoryBufSize = codec.getBits(13);
    if (selectorHistoryBufSize == 0) {
      throw const Ktx2FormatException(
        'ETC1S tables: selector history buffer size is zero.',
      );
    }
    return _Tables(
      endpointPredModel,
      deltaEndpointModel,
      selectorModel,
      selectorHistoryBufRleModel,
      selectorHistoryBufSize,
    );
  }
}

/// `basist::approx_move_to_front`: a fixed-size ring the selector bitstream
/// references by position rather than by value, so a recently-used selector
/// gets a short code without the codec re-sending the value itself.
final class _ApproxMoveToFront {
  _ApproxMoveToFront(int n) : _values = List<int>.filled(n, 0), _rover = n ~/ 2;

  final List<int> _values;
  int _rover;

  int operator [](int index) => _values[index];

  void add(int value) {
    _values[_rover++] = value;
    if (_rover == _values.length) _rover = _values.length ~/ 2;
  }

  void use(int index) {
    if (index == 0) return;
    final x = _values[index ~/ 2];
    final y = _values[index];
    _values[index ~/ 2] = y;
    _values[index] = x;
  }
}

const int _endpointPredRepeatLastSymbol = 4 * 4 * 4 * 4;
const int _endpointPredMinRepeatCount = 3;
const int _endpointPredCountVlcBits = 4;
const int _selectorHistoryBufRleCountThresh = 3;
const int _selectorHistoryBufRleCountBits = 6;
const int _selectorHistoryBufRleCountTotal =
    1 << _selectorHistoryBufRleCountBits;

/// Transcodes one ETC1S slice (one level's worth of 4x4 blocks, RGB only —
/// alpha slices are a separate call the caller composites) straight to
/// RGBA8, without ever materialising ETC1 block bytes in between.
///
/// [sliceData] is the level's compressed bytes (the KTX2 level index's
/// bytes, narrowed to the `ImageDesc`'s RGB slice range). [numBlocksX] /
/// [numBlocksY] and the pixel dimensions come from the image's own
/// description, not from this data.
Uint8List transcodeEtc1sSliceToRgba8({
  required Uint8List endpointsData,
  required int numEndpoints,
  required Uint8List selectorsData,
  required int numSelectors,
  required Uint8List tableData,
  required Uint8List sliceData,
  required int pixelWidth,
  required int pixelHeight,
  required int numBlocksX,
  required int numBlocksY,
}) {
  final palettes = _Palettes.decode(
    endpointsData,
    numEndpoints,
    selectorsData,
    numSelectors,
  );
  final tables = _Tables.decode(tableData);

  final out = Uint8List(pixelWidth * pixelHeight * 4);
  final outView = ByteData.view(out.buffer);

  final codec = BitwiseDecoder(sliceData);
  final selectorHistoryBuf = _ApproxMoveToFront(tables.selectorHistoryBufSize);
  final selectorHistoryFirstSymbolIndex = palettes.selectors.length;
  final selectorHistoryRleSymbolIndex =
      tables.selectorHistoryBufSize + selectorHistoryFirstSymbolIndex;

  var curSelectorRleCount = 0;
  var curPredBits = 0;
  var prevEndpointPredSym = 0;
  var endpointPredRepeatCount = 0;
  var prevEndpointIndex = 0;

  // One slot per block column, one set for even rows and one for odd —
  // `pState->m_block_endpoint_preds[2][num_blocks_x]` in the reference.
  final predBits = [
    List<int>.filled(numBlocksX, 0),
    List<int>.filled(numBlocksX, 0),
  ];
  final predEndpointIndex = [
    List<int>.filled(numBlocksX, 0),
    List<int>.filled(numBlocksX, 0),
  ];

  for (var blockY = 0; blockY < numBlocksY; blockY++) {
    final curArray = blockY & 1;

    for (var blockX = 0; blockX < numBlocksX; blockX++) {
      if ((blockX & 1) == 0) {
        if ((blockY & 1) == 0) {
          if (endpointPredRepeatCount > 0) {
            endpointPredRepeatCount--;
            curPredBits = prevEndpointPredSym;
          } else {
            curPredBits = codec.decodeHuffman(tables.endpointPredModel);
            if (curPredBits == _endpointPredRepeatLastSymbol) {
              endpointPredRepeatCount =
                  codec.decodeVlc(_endpointPredCountVlcBits) +
                  _endpointPredMinRepeatCount -
                  1;
              curPredBits = prevEndpointPredSym;
            } else {
              prevEndpointPredSym = curPredBits;
            }
          }
          predBits[curArray ^ 1][blockX] = (curPredBits >> 4) & 0xFF;
        } else {
          curPredBits = predBits[curArray][blockX];
        }
      }

      final pred = curPredBits & 3;
      curPredBits >>= 2;

      int endpointIndex;
      if (pred == 0) {
        if (blockX == 0) {
          throw const Ktx2FormatException(
            'ETC1S bitstream: left predictor at column 0.',
          );
        }
        endpointIndex = prevEndpointIndex;
      } else if (pred == 1) {
        if (blockY == 0) {
          throw const Ktx2FormatException(
            'ETC1S bitstream: upper predictor at row 0.',
          );
        }
        endpointIndex = predEndpointIndex[curArray ^ 1][blockX];
      } else if (pred == 2) {
        if (blockX == 0 || blockY == 0) {
          throw const Ktx2FormatException(
            'ETC1S bitstream: upper-left predictor at an edge.',
          );
        }
        endpointIndex = predEndpointIndex[curArray ^ 1][blockX - 1];
      } else {
        final deltaSym = codec.decodeHuffman(tables.deltaEndpointModel);
        endpointIndex = deltaSym + prevEndpointIndex;
        if (endpointIndex >= palettes.endpoints.length) {
          endpointIndex -= palettes.endpoints.length;
        }
      }
      predEndpointIndex[curArray][blockX] = endpointIndex;
      prevEndpointIndex = endpointIndex;

      int selectorSym;
      if (curSelectorRleCount > 0) {
        curSelectorRleCount--;
        selectorSym = palettes.selectors.length;
      } else {
        selectorSym = codec.decodeHuffman(tables.selectorModel);
        if (selectorSym == selectorHistoryRleSymbolIndex) {
          final runSym = codec.decodeHuffman(tables.selectorHistoryBufRleModel);
          if (runSym == _selectorHistoryBufRleCountTotal - 1) {
            curSelectorRleCount =
                codec.decodeVlc(7) + _selectorHistoryBufRleCountThresh;
          } else {
            curSelectorRleCount = runSym + _selectorHistoryBufRleCountThresh;
          }
          if (curSelectorRleCount > numBlocksX * numBlocksY) {
            throw const Ktx2FormatException(
              'ETC1S bitstream: selector RLE run is too long.',
            );
          }
          selectorSym = palettes.selectors.length;
          curSelectorRleCount--;
        }
      }

      int selectorIndex;
      if (selectorSym >= palettes.selectors.length) {
        final historyIndex = selectorSym - palettes.selectors.length;
        if (historyIndex >= tables.selectorHistoryBufSize) {
          throw const Ktx2FormatException(
            'ETC1S bitstream: selector history reference is out of range.',
          );
        }
        selectorIndex = selectorHistoryBuf[historyIndex];
        if (historyIndex != 0) selectorHistoryBuf.use(historyIndex);
      } else {
        selectorIndex = selectorSym;
        selectorHistoryBuf.add(selectorIndex);
      }

      if (endpointIndex >= palettes.endpoints.length ||
          selectorIndex >= palettes.selectors.length) {
        throw const Ktx2FormatException(
          'ETC1S bitstream: a codebook index is out of range.',
        );
      }

      final colors = _blockColors(palettes.endpoints, endpointIndex);
      final selector = palettes.selectors[selectorIndex];

      final maxX = (pixelWidth - blockX * 4).clamp(0, 4);
      final maxY = (pixelHeight - blockY * 4).clamp(0, 4);
      for (var y = 0; y < maxY; y++) {
        final py = blockY * 4 + y;
        for (var x = 0; x < maxX; x++) {
          final px = blockX * 4 + x;
          outView.setUint32(
            (py * pixelWidth + px) * 4,
            colors[selector.at(x, y)],
            Endian.little,
          );
        }
      }
    }
  }

  return out;
}
