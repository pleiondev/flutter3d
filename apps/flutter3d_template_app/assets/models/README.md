# Empty on purpose

This application is the template **without** the models. A project scaffolded
from a template in `apps/flutter3d_editor/assets/templates` gets its models
copied in here; the seed itself ships none, which is what its own level test
says when it skips.

The directory still has to exist. `pubspec.yaml` declares `assets/models/`, and
Flutter refuses to analyse a package that names an asset directory which is not
there — with `unable to find directory entry in pubspec.yaml`, at a point where
nothing says the cause is an empty folder. Git does not track directories, only
files, so on a fresh checkout this file is the whole reason the directory
arrives.

Deleting it turns every clean clone red.
