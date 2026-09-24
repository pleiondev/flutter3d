/// The light list: every scene light in one texture, and which rows a draw
/// reads — `gfx-74n`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// **What the cap actually was.** Eight is the cap on one *draw*, not on a
/// scene: `gfx-12n` already picks the eight lights that reach each object, so a
/// night map may carry two hundred torches with every object lit by its own
/// eight. What that cannot do is light one object with more than eight, and the
/// place it shows is a surface large enough to touch many at once — a ground
/// plane whose bounding sphere reaches every torch scores them all at distance
/// zero and keeps the eight brightest.
///
/// **A texture rather than a wider uniform block.** The four `vec4` arrays in
/// `FragInfo` are uploaded on every draw, so widening them to thirty-two lights
/// would be a two-kilobyte upload per draw in every scene, including every
/// scene with one light. The light *data* is the same for every draw in the
/// frame, so it belongs in something built once a frame; what differs per draw
/// is which of them reach it, and that is a list of row numbers.
///
/// **Built once a frame, and only when a scene overflows.** A scene inside the
/// eight slots never makes a texture, binds a one-by-one stand-in, and runs the
/// loop it has always run over the arrays it has always read. That is why not
/// one of the forty-four recorded frames moves: the path they take is
/// untouched, rather than compared against afterwards.
part of 'renderer.dart';

/// Floats one light's row holds: four texels of four.
const int _kLightRowFloats = 16;

/// The tallest light list the cells may make: the height WebGL 2 promises,
/// twice over, which every backend here exceeds.
const int _kMaxListRows = 4096;

extension _LightList on Renderer {
  /// Builds this frame's light texture from [lights]' candidates.
  ///
  /// Returns null when the scene fits in the slots, which is the case that must
  /// cost nothing: no allocation, no upload, no texture.
  ///
  /// Rows are candidates in scene order, so a draw's tail — which
  /// `LightBuffer.extraIndices` gives as candidate indices — is a list of row
  /// numbers with no mapping in between.
  TextureHandle? _buildLightList(LightBuffer lights) {
    final count = lights.candidates.length;
    if (count <= LightBuffer.maxLights) return null;

    // **Compared, not keyed on `SceneNode.changeEpoch`.** The epoch covers a
    // light that moved, appeared or vanished, and nothing else: colour,
    // intensity, range and the cone are plain fields on `LightNode` that
    // advance no counter, so a torch flickering in place kept the row it was
    // first uploaded with for as long as nothing else in the scene moved.
    // Writing the rows costs sixteen floats a light, far less than the upload
    // it decides about, and the comparison is what makes skipping it honest.
    // `L6`: the view's cells after the light rows, headers then entries, in
    // the one texture a lit stage already samples. A view so crowded that
    // they would outgrow a texture every backend can make reads the draws'
    // own tails instead.
    if (_clustersActive &&
        count + LightClusters.headerRows + _lightClusters.entryRows >
            _kMaxListRows) {
      _clustersActive = false;
    }
    final rowCount = _clustersActive
        ? count + LightClusters.headerRows + _lightClusters.entryRows
        : count;
    final length = rowCount * _kLightRowFloats;
    if (_lightListScratch.length < length) {
      _lightListScratch = Float32List(length);
    }
    final rows = Float32List.sublistView(_lightListScratch, 0, length);
    for (var i = 0; i < count; i++) {
      lights.writeCandidateRow(i, rows, i * _kLightRowFloats);
    }
    if (_clustersActive) {
      _lightClusters.write(rows, count * _kLightRowFloats);
      _clusterHeaderRow = count;
      _clusterEntryRow = count + LightClusters.headerRows;
    }
    if (_lightListTexture != null && _sameRows(rows, _lightListUploaded)) {
      return _lightListTexture;
    }

    final previous = _lightListTexture;
    _lightListTexture = device.createTextureFromPixels(
      width: 4,
      height: rowCount,
      format: TextureFormat.r32g32b32a32Float,
      pixels: ByteData.sublistView(rows),
    );
    _lightListUploaded = Float32List.fromList(rows);
    _lightListRows = rowCount;
    // After the new one is made rather than before: a device that refuses the
    // upload leaves the frame with the texture it had rather than with none.
    if (previous != null) _destroyAfterFrame(previous);
    return _lightListTexture;
  }

  static bool _sameRows(Float32List a, Float32List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Binds the list a draw reads, and the stand-in when it reads none.
  ///
  /// **Always, for both halves.** A declared sampler nobody binds is a native
  /// crash on Metal rather than a black texture, and a declared block nobody
  /// writes is the other way this repository has already drawn a wrong picture
  /// with no error anywhere. A draw with no tail binds a count of nought and a
  /// one-by-one texture it never reads.
  void _bindLightList(
    PassEncoder pass,
    ShaderHandle stage,
    LightBuffer drawLights,
    TextureHandle? texture,
  ) {
    // `L6`: a draw in a clustered view reads its tail from the cell, and
    // hands the shader the rows its slots hold so a cell's copy is skipped.
    final clustered = _clustersActive && texture != null;
    final count = texture == null || clustered
        ? 0
        : math.min(drawLights.extraCount, LightBuffer.maxExtraLights);

    _lightListParams[0] = count.toDouble();
    _lightListParams[1] = count == 0 && !clustered ? 0.0 : 0.25;
    _lightListParams[2] = count == 0 && !clustered ? 0.0 : 1.0 / _lightListRows;
    _lightListParams[3] = 0.0;
    _lightListInfo.clusterViewProjection.setAll(
      0,
      _lightClusters.viewProjection.storage,
    );
    _lightListInfo.clusterGrid
      ..[0] = LightClusters.tilesX.toDouble()
      ..[1] = LightClusters.tilesY.toDouble()
      ..[2] = LightClusters.slices.toDouble()
      ..[3] = clustered ? 1.0 : 0.0;
    _lightListInfo.clusterDepth
      ..[0] = _lightClusters.near
      ..[1] = _lightClusters.sliceScale
      ..[2] = _clusterHeaderRow.toDouble()
      ..[3] = _clusterEntryRow.toDouble();
    for (var i = 0; i < LightBuffer.maxLights; i++) {
      _lightListInfo.slotRows[i] = i < drawLights.count
          ? drawLights.slotCandidates[i].toDouble()
          : -1.0;
    }
    for (var i = 0; i < LightBuffer.maxExtraLights; i++) {
      _lightListIndices[i] = i < count
          ? drawLights.extraIndices[i].toDouble()
          : 0.0;
      _lightListScales[i] = i < count ? drawLights.extraScales[i] : 0.0;
    }

    pass
      ..bindBlock(stage, _lightListInfo)
      ..bindTexture(
        stage,
        'light_list_texture',
        texture ?? fallbackBlack,
        // Nearest and clamped: a row holds a light's numbers, and a filtered
        // read halfway between two rows would invent a light that is the
        // average of two.
        sampler: SamplerOptions.nearestClamp,
      );
  }
}
