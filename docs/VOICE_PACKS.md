# Voice pack workflow

Voice packs are discovered automatically from
`assets/audio/voice_packs/*_manifest.json`. Adding a correctly formatted pack
to that directory makes its language and voice appear in **Setup > Audio**.

## Add a pack

1. Choose a stable lowercase pack ID, such as `coach_es` or `guest_name_en`.
2. Convert every clip to mono, 44.1 kHz, 16-bit PCM WAV. Trim callouts to
   0.2–2.0 seconds, add short fades, and normalize peaks to -3 dBFS.
3. Put the WAV files directly in `assets/audio/voice_packs/`. Prefixing every
   filename with the pack ID prevents collisions.
4. Add `<pack_id>_manifest.json` in the same directory using schema version 1.
5. Run `flutter test test/audio_asset_contract_test.dart` and then
   `flutter test`.

The directory is intentionally flat. Flutter bundles new files placed there
without needing another `pubspec.yaml` entry.

## Required cue IDs

Every complete pack should map these callouts:

`callout_shot`, `callout_sprawl`, `callout_stance`, `callout_circle`,
`callout_down_block`, `callout_fake`, `callout_level_change`,
`callout_snap_down`, `callout_high_knees`, `callout_foot_fire`, and
`callout_hand_fight`.

It should also map `ad_lib_1` through `ad_lib_5` and provide one `whistle`.
Custom recordings made by a user always override the selected pack.

## Manifest example

```json
{
  "schemaVersion": 1,
  "id": "coach_es",
  "name": "Entrenador clásico",
  "languageCode": "es",
  "languageName": "Español",
  "attribution": "Voice performance by Example Name",
  "callouts": {
    "callout_shot": "assets/audio/voice_packs/coach_es_callout_shot.wav",
    "callout_sprawl": "assets/audio/voice_packs/coach_es_callout_sprawl.wav"
  },
  "adLibs": {
    "ad_lib_1": "assets/audio/voice_packs/coach_es_ad_lib_1.wav"
  },
  "whistle": "assets/audio/voice_packs/coach_es_whistle.wav"
}
```

Continue the `callouts` and `adLibs` objects with all required IDs. Asset paths
are project-relative and must point to files included in the app bundle.

Only distribute a celebrity or guest voice pack when the recording and the
person's name/likeness are licensed for use in the app. Use `attribution` for
the required credit line.
