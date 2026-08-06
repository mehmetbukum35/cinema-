# Screenshots

Store listing and README visuals for **cinema+** / Ne İzlesem?.

Capture on a **release** or profile build against a healthy API. Hide the debug banner (`flutter run --release` or take from a device build). Prefer dark theme (default brand look) unless the listing explicitly shows light mode.

## Required frames

| Filename (suggested) | Screen | What must be visible |
|----------------------|--------|----------------------|
| `01-browse.png` | Browse / Keşfet | Header, mood row, at least one rail with posters |
| `02-swipe.png` | Swipe | Rating card mid-stack, clear genre/title |
| `03-search.png` | Search | Query or filters + result list/grid |
| `04-social.png` | Social / Birlikte | Friends or activity feed (non-empty if possible) |
| `05-detail.png` | Movie/TV detail sheet | Poster/backdrop, title, primary actions |
| `06-profile.png` | Profile | Header + Top 20 or library rail |

Optional: `07-match.png`, `08-library.png`, `09-taste-dna.png`.

## Sizes

| Store | Priority size | Notes |
|-------|---------------|--------|
| Play phone | **1080 × 1920** (9:16) | Upload 2–8 phone screenshots |
| Play 7" / 10" tablet | Optional | Only if you market tablet |
| App Store iPhone 6.7" | **1290 × 2796** | Or use Xcode / Simulator Export |
| App Store iPhone 6.5" | **1284 × 2778** | Fallback set if no 6.7" |
| App Store iPad | Only if iPad is supported in binary |

Same composition can be scaled; do not letterbox with random wallpaper.

## How to capture

```bash
# Example: phone-shaped emulator, then OS screenshot / Flutter DevTools
flutter run --release \
  --dart-define=API_BASE_URL=https://YOUR_API \
  --dart-define=WEB_PROFILE_BASE_URL=https://YOUR_API/profile
```

1. Sign in with a **demo** account that has ratings, watchlist, and a friend signal (so Social/Profile are not empty).
2. Capture each required frame; crop to device screen only (no desktop chrome).
3. Drop PNGs into this folder using the names above.
4. Tick the screenshot section in [STORE_RELEASE_CHECKLIST.md](STORE_RELEASE_CHECKLIST.md).

## Status

- [ ] `01-browse.png`
- [ ] `02-swipe.png`
- [ ] `03-search.png`
- [ ] `04-social.png`
- [ ] `05-detail.png`
- [ ] `06-profile.png`

Until boxes are checked, run the app locally to preview these surfaces.
