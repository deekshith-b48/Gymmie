# Notices

Gymmie is free software under the **GNU Affero General Public License v3.0 or later** (see [LICENSE](LICENSE)). The complete
source code is published, and anyone who uses the hosted service can get it. The service, support, message credits and
subscriptions are what Gymmie charges for, not the code.

## What the member training log is built from

- **openGym** by Duarte Santos, AGPL-3.0-or-later. The member app's workout log, settings, activity heatmap, units, equipment
  and backup format are a Dart port of openGym's behaviour. https://github.com/DuarteSantos8/openGym
  (Distribution through app stores is allowed by openGym's additional permission under AGPL section 7.)
- **GymMane** by InlitX, GPL-3.0-only with an attribution term. The "Choose a focus" flow comes from it.
  **Based on GymMane by InlitX** (shown in the app's About screen, as the licence requires).
- **MuscleMap** by Melih Colpan, MIT. The body-diagram muscle outlines.
- **ExerciseDB data** (exercise names, body parts, equipment, muscle weights), MIT, as listed in openGym's NOTICE.

## What is NOT included

- The exercise **pictures and animations** (gymvisual.com, Aliaksandr Makatserchyk) are licensed for use inside openGym only.
  Gymmie does not bundle them in the app. The app plays them from a media host the operator runs (`OPENGYM_PUBLIC_URL`), and the server
  only hands out their addresses when the operator sets `EXERCISE_MEDIA_LICENSED=1`, which means they hold a licence from gymvisual.com.
  Without it the exercise library works as text and body-map filters.

## Fonts

- **Poppins** (SIL Open Font License 1.1), used to print the rupee sign in PDF invoices.

## Libraries

Flutter and the Dart/Node packages Gymmie uses keep their own licences; the full list is in the app under
Settings > About > Open-source licences.
