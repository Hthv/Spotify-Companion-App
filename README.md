# Spotify Companion

A native macOS display and remote for the Spotify desktop app. Spotify still plays
the audio; this app reads what's playing over AppleScript and sends controls back.

> Not affiliated with, endorsed by, or sponsored by Spotify. Spotify is a trademark
> of Spotify AB. Lyrics come from [LRCLIB](https://lrclib.net), a community lyrics
> database.

Requires macOS 14 (Sonoma) or later and the Spotify desktop app. Runs on Apple
Silicon and Intel.

## Install

1. Download the zip, double-click it, and drag **Spotify Companion** into
   Applications.
2. Open it. The app isn't notarized, so macOS warns that it can't verify it.
   Dismiss the warning, then go to System Settings › Privacy & Security and click
   **Open Anyway**. You only do this once per version.
3. Allow it to control **Spotify** when asked.

Playback controls, lyrics and every style work without signing in. Signing in
(below) adds Liked Songs, add to playlist and recently played.

## Styles

Each style changes the whole design (type, layout, cover treatment, controls,
progress bar, dividers, ornament and motion), not just the colors. Each one has its
own palettes plus **Album Colors** (from the cover) and **Album Blur** (the cover,
blurred, behind everything). Every style remembers its own color choice.

| Style | Character |
| --- | --- |
| Swiss Design | Helvetica Neue, flush-left grid, hairlines, flat signal red |
| Minimalism | Light system type, centered, thin outline controls, nothing extra |
| Luxury Typography | Didot and Baskerville italic, tracked small caps, gold frame and hairlines |
| Ethereal | Avenir Next UltraLight, glass controls, glowing cover, drifting light |
| Wabi Sabi | Hoefler Text and lowercase Gill Sans, paper grain, an ensō, uneven cover corners |
| Y2K Aesthetic | Rounded bold type, chrome title, glossy pill buttons, sparkles |
| Editorial Design | Heavy serif headlines, Futura kickers, double rules, "Fig. 1" captions |

Pick a style and its colors from the two drop-downs in the header. The sliders icon
opens **Customize**: show or hide the cover, lyrics, album, progress, shuffle and
repeat, volume, like and add, the equalizer and ambient motion; put the cover on
the left or right; change the text size.

## Spotify account (optional)

Liking songs, adding them to playlists and the recently played list on Home use
Spotify's Web API, which needs a Client ID from your own developer app:

1. Create an app at <https://developer.spotify.com/dashboard>.
2. Add the Redirect URI `http://127.0.0.1:43821/callback` and tick **Web API**.
3. Click the person icon in the header, paste the Client ID, press Connect, and
   approve in the browser.

Spotify's Development Mode needs the app owner to have Premium and allows up to
five listed users (add yourself under User Management). The sign-in uses PKCE, so
there's no client secret. The refresh token is kept in the login keychain. Ad-hoc
signed rebuilds may ask once for keychain access.

## Run

Open `SpotifyCompanion.xcodeproj` in Xcode and press ⌘R, or build from the terminal:

```bash
xcodebuild -project SpotifyCompanion.xcodeproj -scheme SpotifyCompanion -configuration Release -derivedDataPath build build
ditto "build/Build/Products/Release/Spotify Companion.app" "/Applications/Spotify Companion.app"
```

The first time it talks to Spotify, macOS asks to let **Spotify Companion** control
**Spotify**. Click Allow. If you denied it, turn it on under System Settings ›
Privacy & Security › Automation, or reset the prompt:

```bash
tccutil reset AppleEvents com.hoventan.SpotifyCompanion
```

The app is ad-hoc signed ("Sign to Run Locally"), so macOS may ask again after a
rebuild. Picking your Apple ID team under Signing & Capabilities stops that.

## Layout

| Path | What it does |
| --- | --- |
| `Spotify/AppleScriptRunner.swift` | Runs AppleScript on a background queue; caches the compiled poll script |
| `Spotify/PlayerSnapshot.swift` | The one read script, and parsing its reply into `Track` / `PlayerSnapshot` |
| `Spotify/SpotifyService.swift` | Polling (1 s, plus Spotify's `PlaybackStateChanged` notification), position interpolation, controls |
| `Artwork/` | Cover download and palette extraction for the Auto theme |
| `Lyrics/` | LRCLIB client (exact match, then search; a busy server falls back instead of failing), LRC parser, lyrics store |
| `Views/Lyrics/` | Apple Music style synced lyrics: staggered spring scroll, distance blur, interlude dots, click a line to seek, scroll to browse |
| `Account/` | Web API sign-in (PKCE, loopback callback on 127.0.0.1:43821), keychain, Liked Songs, playlists, recently played |
| `Design/Styles.swift` | The seven styles as tokens: fonts, composition, cover, control, progress, rule, ornament, motion, palettes |
| `Design/Theme.swift` | A style plus a color choice (palette, Album Colors, Album Blur) resolved into what views read |
| `Design/Appearance.swift`, `Preferences.swift` | Chosen style, per-style colors, and the Customize settings |
| `Design/Kit.swift` | Shared pieces: labels, titles, rules, cards, the staggered reveal |
| `Views/` | Root, header (style, colors, customize, account), Home, Now Playing (split, centered and lyrics layouts), backdrop and ornaments, artwork, progress bar, controls, like and playlist buttons, account sheet, status screens |
| `Config/` | `Info.plist` (Automation usage string) and entitlements (`automation.apple-events`) |
| `Scripts/make-icon.swift` | Regenerates the app icon |

The app is not sandboxed (a sandboxed app would also need a temporary-exception
entitlement to script Spotify). Hardened runtime is on.

## Lyrics

Lyrics come from LRCLIB and are cached on disk, so songs you've seen before still
show during an outage. If LRCLIB is unreachable the app retries in the background,
honouring its rate limits, and shows "Loading lyrics automatically…" above the
cover. A song with no lyrics (or none after a minute) shows the cover layout with
"No lyrics provided for this song".

## Shortcuts

| Keys | Action |
| --- | --- |
| Space | Play / pause |
| ⌘→ / ⌘← | Next / previous track |
| ⇧→ / ⇧← | Forward / back 10 seconds |
| ⌘↑ / ⌘↓ | Volume up / down; ⌥⌘↓ mutes |
| ⌘S / ⌘R | Shuffle / repeat |
| ⌥⇧B | Add to / remove from Liked Songs |
| ⌘L | Show or hide lyrics |
| ⇧⌘A | Show or hide the cover |
| ⇧⌘H / ⇧⌘P | Home / Player |
| ⌘1–⌘7 | Swiss, Minimalism, Luxury, Ethereal, Wabi Sabi, Y2K, Editorial |

Click the cover to play or pause, click a lyric line to jump to it, hover the
progress bar for a time readout, hover the speaker icon for the volume slider, and
click a recently played cover on Home to play it.

## Not built yet

From the project brief: playback on other devices and the queue over the Web API,
menu-bar mini player, visualizer.
For anything beyond personal use, check Spotify's developer policy and keep
Spotify attribution.

## License

[MIT](LICENSE). Use, change and share it freely; keep the copyright notice.
