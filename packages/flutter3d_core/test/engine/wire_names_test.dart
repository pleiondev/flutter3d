// The names the frame reports and a plugin's graph declares are spelled the
// American way, like every identifier: they are compared as text, so a
// British `colour` in one of them is a resource nobody finds.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

void main() {
  test('the frame resources are named in American spelling', () {
    expect(FrameResourceIds.hdrColor, const ResourceId('f3d.hdr_color'));
    expect(FrameResourceIds.sceneColor, const ResourceId('f3d.scene_color'));
  });

  test('the steps and their passes are named in American spelling', () {
    expect(RenderStep.colorGrade.name, 'f3d.color_grade');
    expect(RenderStep.sceneColorCopy.name, 'f3d.scene_color_copy');
    expect(RenderStep.sceneColorCopy.passes, <String>{'scene color copy'});
    for (final step in RenderStep.values) {
      expect(step.name, isNot(contains('colour')), reason: step.name);
    }
  });
}
