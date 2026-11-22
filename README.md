# Focus Reels

An Android app that counts and limits short videos (Instagram Reels, YouTube Shorts, Snapchat Spotlight,
Netflix Clips, TikTok, and Shorts in browsers), built with Flutter and a native Kotlin accessibility service.
Everything runs on the phone. No account, no ads.

## Features
- Live counter over the reel app (movable by press-and-hold), with a daily recap notification
- Counts a reel only when you reach a new one; going back to one you already saw does not count
- Plans: Track only, My limits, Block all, One reel, Curious, Paused
- Per-app: always block reels, hide the Reels/Shorts tab, daily timers for any app, block action (back, home, lock)
- Optional: block or count Shorts opened in Chrome, Samsung Internet, Brave, Edge, Firefox, Opera
- Stats by day, week, month and year, screen time for all apps, block history, backup and restore
- Editable detection rules, in case an app update breaks counting

## Build
```
flutter pub get
flutter build apk --release
```
Requires the Flutter SDK and the Android SDK. The release build is signed with the debug key; add your own
signing config before publishing anywhere.

## Permissions it asks for
Accessibility (to see when a reel is on screen), display over other apps (counter and block screen),
notifications, battery-optimisation exemption and usage access (screen time). On Android 13+ an app installed
from a file also needs "Allow restricted settings" (App info > three dots) before Accessibility can be turned on.

## Layout
- `lib/` Flutter UI (Today, Stats, Apps, Rules, Health)
- `android/app/src/main/kotlin/.../` accessibility service, rule engine, block screen, counter view
- `server/server.js` optional friends/buddy server (off by default)
