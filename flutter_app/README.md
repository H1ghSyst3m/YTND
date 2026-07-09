# YTND Flutter App

Android-first mobile companion for YTND with library sync, queue management, direct YouTube sharing, and always-reachable server settings.

## Core features
- Login against `/api/login` with username/password and persistent session cookie reuse
- Material 3 app shell with Library, Queue, and Settings as primary destinations
- Editable server settings even when the saved server is unreachable or the session expired
- Structured API error handling with actionable connection states instead of raw exceptions
- Manual and interval-based sync with network checks and optional WiFi-only background sync
- Song library with search, cover loading, sync, delete, and redownload actions
- Queue management with live WebSocket progress, start/remove/clear actions, and pending shared links
- Android share intent support for YouTube links from the Share Sheet and supported YouTube link opens

## Platform scope
v1 is Android-focused. iOS share extensions and desktop-specific share flows are intentionally left for a later cross-platform pass.

## Default storage path
`/storage/emulated/0/Music/YTND`

## Run
```bash
cd flutter_app
flutter pub get
flutter run
```
