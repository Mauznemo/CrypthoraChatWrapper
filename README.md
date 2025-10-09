# CrypthoraChat Wrapper

Wrapper for [CrypthoraChat](https://github.com/Mauznemo/CrypthoraChat) to get push notifications even in doze mode on Android.

## Features
### Current
- Realtime push notifications on Android even in doze mode/deep idle

### Planned
- Easy adding and switching between CrypthoraChat servers.
- Popup on app open if new update for wrapper is available

## Installation
Go to the [releases](https://github.com/Mauznemo/CrypthoraChatWrapper/releases/latest) tab and download the `apk` for the newest one. 

## Tech stack
- [Flutter](https://flutter.dev/)
- [ntfy](https://docs.ntfy.sh/install/) on server side of sending notifications (included in CrypthoraChat `docker-compose.yaml`)

## Developer Setup
If you wan to contribute or make changes this is how to set everything up.
1. clone the repo and open the project in any editor that supports flutter (eg Android Studio or VS Code)
2. For local testing you can clone the [CrypthoraChat](https://github.com/Mauznemo/CrypthoraChat) and start it in Docker Desktop with `docker-compose up -d --build`
3. Connect you phone via USB with USB debugging enabled and run `adb reverse tcp:3000 tcp:3000` and `adb reverse tcp:8181 tcp:8181`
4. Now you can run the flutter app and use `http://localhost:3000` for the server url and `ws://localhost:8181` for the ntfy url (localhost urls only work when the flutter app is build in debug mode)