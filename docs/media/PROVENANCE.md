# Screenshot provenance and privacy

The gallery contains **genuine Flutter app pixels**, taken from the authorized Vivo Android 16 staging installation of Little Rest. The published captures show **empty-state screens with zero recorded sleep sessions**, before any later testing. No baby names, actual session timestamps, account email addresses or private notifications appear.

- Captured directly from the staging application after signed GitHub APK deployment (Android run [39663684759](https://github.com/analienx/baby-sleep-tracker/actions/runs/39663684759)). The `com.analienx.baby_sleep_tracker.staging` app is isolated from the existing preview.
- Three source screens are Today, Trends, and Settings in dark mode. No face, child record or actual family data was included.
- `scripts/render_readme_media.py` **crops status and gesture bars** (removing time, personal device notification icons and system controls) and scales the actual UI, without replacing or generating text inside the screenshots.
- The hero artwork frames two of those genuine screens with a decorative gradient, a simple original moon mark, and editorial captions. This is marketing design, **not a fabricated app interface**.
- App typography is bundled Inter (SIL OFL — `assets/fonts/OFL.txt`). On-device screenshots may differ from iPhone or future revisions.
- These are **pre-release development images**, not proof of completed multi-caregiver sharing, account erasure, security approval or iOS provisioning.

To regenerate after a UI change, capture fresh **audited, synthetic/empty-state** screens from a dedicated QA installation, then:

```sh
python -m pip install Pillow
python scripts/render_readme_media.py /path/to/verified-empty-screen-pngs docs/media
```

Examine every input before publication. **Never automatically publish arbitrary personal-device or emulator screenshots.** In particular, reject OS crash dialogs, real child sleep records, account identifiers, personal notifications and unrelated app windows.
