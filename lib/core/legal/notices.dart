// The notices a user can read inside the app (Settings > Open-source licences), next to the licences of every library.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The attribution GymMane's licence requires wherever the app shows its legal notices.
const gymManeAttribution = 'Based on GymMane by InlitX';

const _notice = '''
Gymmie is free software under the GNU Affero General Public License v3.0 or later. Its source code is published.

The member training log is built from:
- openGym by Duarte Santos (AGPL-3.0-or-later)
- GymMane by InlitX (GPL-3.0-only). $gymManeAttribution
- MuscleMap by Melih Colpan (MIT): body-diagram outlines
- ExerciseDB data (MIT): exercise names, body parts and muscles

Poppins font: SIL Open Font License 1.1.

The exercise pictures and animations of gymvisual.com are not part of Gymmie.
''';

/// Adds Gymmie's own notice to Flutter's licence list. Call once at start-up.
void registerNotices() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['Gymmie'], _notice);
  });
}

void showNotices(BuildContext context, {String? version}) => showLicensePage(
  context: context,
  applicationName: 'Gymmie',
  applicationVersion: version,
  applicationLegalese: gymManeAttribution,
);
