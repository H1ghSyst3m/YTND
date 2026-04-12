# YTND Flutter App

Android sync client and song library manager for YTND.

## Core features
- Login against `/api/login` with username/password
- Persistent session cookie reuse for API requests
- Manual and interval-based sync with network checks
- Real Android background sync with WorkManager (interval from settings, optional WiFi-only)
- Song library view with server-side delete + local delete
- Download screen with queue management, share intent support, and live progress updates
- Settings for server URL, credentials, sync interval and storage path

## Default storage path
`/storage/emulated/0/Music/YTND`

## Run
```bash
cd flutter_app
flutter pub get
flutter run
```
