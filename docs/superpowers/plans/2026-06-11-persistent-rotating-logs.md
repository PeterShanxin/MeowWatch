# Plan: Persistent rotating diagnostic logs + in-app setting

Branch: `feat/persistent-rotating-logs` (off `main` after v0.22.2-alpha).

## Why
The sync log (`DebugLog.temp('meowwatch_sync.log')`) lives in OS temp and
**truncates on every launch**, so the laggy co-watch session keeps getting
wiped before we can read it. Make logging a real, always-on, rotating feature
so the evidence is already saved when the intermittent A/V lag next strikes.

## Confirmed design (user approved 2026-06-11)
1. **Rotating logs**: keep the last **10** session logs (timestamped filenames)
   in a stable app dir (NOT temp). Auto-delete older.
2. **Levels**: `Off / On (neat) / On (verbose)` — **default `verbose`**.
   - verbose = current full trace (`<<` `>>` `FOLLOW` lines).
   - neat = drop per-heartbeat spam (`<<`/`>>` and `FOLLOW ... apply=false`),
     keep meaningful events (apply=true, reconnect/drop, errors, log markers).
3. **Export logs** button in the gear menu → one-click bundle to send.

## Settings pattern (already in repo — mirror it)
- Keys live in `lib/core/data/settings_store.dart` as `const String k...Key`.
- `SettingsStore` abstract: `Future<String?> get(key)` / `Future<void> set(key,value)`.
- `home_screen.dart` `_initSettings()` reads each key into a state field; gear
  menu (`player_menu_button.dart`) gets value + `onChanged`; on change →
  `setState` + `widget.settings.set(key, value)`. Copy this for `log_level`.

## File map / steps (TDD: test first each step)
1. `lib/core/debug/log_level.dart` (new): `enum LogLevel { off, neat, verbose }`
   + `LogLevel logLevelFromName(String?)` (default verbose) + `.storageName`.
   Pure → unit test `test/core/debug/log_level_test.dart`.
2. `lib/core/debug/debug_log.dart` (rewrite): hold a mutable `LogLevel`; a pure
   classifier `bool isVerboseOnly(String line)` (true for lines starting `<<`/
   `>>` or containing `apply=false`); `call()` drops verbose-only lines when
   level==neat and everything when off. Add `DebugLog.inDir(dir, baseName, retain)`:
   `start()` writes a NEW `meowwatch_sync-<stamp>.log`, prunes to newest `retain`.
   Keep all I/O guarded. Tests: rotation/prune + level filtering (use a temp dir).
3. `settings_store.dart`: add `kLogLevelSettingKey = 'log_level'`.
4. `home_screen.dart`: build the DebugLog in the app support dir
   (`getApplicationSupportDirectory()/logs`), read `log_level` in `_initSettings`,
   apply to the log live, pass value + onChanged to the gear menu.
5. `player_menu_button.dart`: add a 3-way control (Off/Neat/Verbose) + an
   "Export logs" button (zip the logs dir via `archive` → save via
   `file_selector` getSaveLocation; or reveal folder). Widget tests for both.
6. Version bump (feat = MINOR): `0.22.2-alpha → 0.23.0-alpha` in pubspec +
   app_version.dart + CHANGELOG (new top entry). Keep `-alpha`.
7. `flutter analyze` clean + full `flutter test` green. Manual: gear menu shows
   the control, switching persists across relaunch, Export produces a zip.
8. PR → Copilot review → CI green → merge → tag `v0.23.0-alpha` → verify R2 →
   cleanup. (Per docs/AGENT_GUIDE.md release flow.)

## Notes
- `path_provider` + `archive` + `file_selector` are already dependencies.
- The Desktop `Save sync log.bat` becomes redundant once Export ships (leave it).
- Still hunting the co-watch A/V lag (solo clean, peer = lag, condition-dependent,
  NOT a regression in `decideFollow`); this feature is what finally captures it.
