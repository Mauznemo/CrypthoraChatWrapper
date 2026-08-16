# Project
The wrapper Flutter (Android) app for an open-source self-hostable E2EE chat app for friends and family.

- slang for localization, strings in lib/i18n/{en,de}.i18n.json (English is the base locale)
    - Keys are camelCase, placeholders use `$var` (or `${var}` when followed by a word char)
    - After editing the JSON run `dart run slang` to regenerate lib/i18n/strings.g.dart
- Custom reusable widgets in lib/widgets/, widgets that are unique to a page they are in a sub dir with that pages name
- For new pages try using a similar code structure (mainly for the UI code) to the existing ones that might be similar, they should also visually match
- When defining widgets or classes put all the vars on top of the constructor not the other way around
- Rest of structure:
    - utils in lib/utils
    - services in lib/services
    - helpers in lib/helpers
    - freezed (add if needed) models in lib/models
    - modals or sheets in lib/modals
    - Some more used only rarely: lib/animations, lib/camera, lib/config, lib/styles
- The App is not in production yet so saved data can break
- Releases are cut with `./scripts/release.sh`, which tags and pushes; GitHub Actions builds and publishes. `version:` in pubspec.yaml is the source of truth, its `+n` build number is ignored (CI derives the versionCode). Changelogs come from `feat:`/`fix:`/`refactor:` commit subjects, so keep writing them that way.
- If at any point a DB is needed it will be objectbox with all models in lib/src/models
- Push notifications are built in a separate isolate. Any state both it and the UI isolate touch (unread counts, pending notifications) must go through `SharedPreferencesAsync`, not `SharedPreferences` — the latter hands each isolate its own cached snapshot, so writes stay invisible to the other side.
- `person_shortcut_creator` is a sibling repo pulled in as a git dependency, so plugin changes only reach the app after they are pushed and `flutter pub upgrade person_shortcut_creator` is run.
- The wrapper/web-app bridge is `window.*` functions the wrapper calls plus `callHandler` names the web app calls; the full contract is typed in the web app's `src/app.d.ts`, keep both sides in sync.
- When defining widgets or classes put all the vars on top of the constructor and not the other way around.
   Update this or other CLAUDE.mds if the info in here changes or something new is worth adding if it will be needed for **every** later session. Do **not** clutter it with one of info or things that are just common sense or easy to figure out without having it here. If you think something one off needs explaining the dart docs with `///` is the right place, not this file.