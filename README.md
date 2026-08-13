# CrypthoraChat Wrapper

Wrapper for [CrypthoraChat](https://github.com/Mauznemo/CrypthoraChat) to get push notifications even in doze mode on Android.

## Features
### Current
- Realtime push notifications on Android even in doze mode/deep idle
- Two push providers to choose from: Google FCM or ntfy/UnifiedPush

### Planned
- Easy adding and switching between CrypthoraChat servers.
- Popup on app open if new update for wrapper is available

## Installation
Go to the [releases](https://github.com/Mauznemo/CrypthoraChatWrapper/releases/latest) tab and download the `apk` for the newest one. 

## Push providers
On the "Set Server" screen you pick where notifications come from:

- **Firebase (Google FCM)** — recommended. Nothing else has to be installed and notifications are far more reliable. Only offered if the CrypthoraChat server you entered has FCM configured, see [Setting up FCM](https://github.com/Mauznemo/CrypthoraChat#setting-up-fcm) in the server repo.
- **ntfy / UnifiedPush** — needs the [ntfy app](https://github.com/binwiederhier/ntfy-android/releases/latest) installed, pointed at your ntfy server and excluded from battery optimization. Keeps everything on your own infrastructure.

The app has **no `google-services.json` baked in**. It asks the server it is pointed at for the Firebase client values (`GET /api/push-config`) and initializes Firebase at runtime, which is why the same prebuilt apk works with any self hosted CrypthoraChat instance.

Either way the push only contains metadata (sender, chat id, timestamp, avatar url) — never message content. The notification text is built on device.

## Tech stack
- [Flutter](https://flutter.dev/)
- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging) or [ntfy](https://docs.ntfy.sh/install/) on server side of sending notifications (ntfy is included in CrypthoraChat `docker-compose.yaml`)

## Developer Setup
If you wan to contribute or make changes this is how to set everything up.
1. clone the repo and open the project in any editor that supports flutter (eg Android Studio or VS Code)
2. For local testing you can clone the [CrypthoraChat](https://github.com/Mauznemo/CrypthoraChat) and start it in Docker Desktop with `docker-compose up -d --build`
3. Connect you phone via USB with USB debugging enabled and run `adb reverse tcp:3000 tcp:3000` (and `adb reverse tcp:8181 tcp:8181` if you want to test the ntfy provider)
4. Now you can run the flutter app and use `http://localhost:3000` for the server url and `ws://localhost:8181` for the ntfy url (localhost urls only work when the flutter app is build in debug mode)

No `google-services.json` and no `com.google.gms.google-services` Gradle plugin are needed — Firebase is initialized at runtime from the config the server hands out. To test FCM locally, set `FCM_CLIENT_CONFIG` and `FCM_SERVICE_ACCOUNT` on your local CrypthoraChat instance.