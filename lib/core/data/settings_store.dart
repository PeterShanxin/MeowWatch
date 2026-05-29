/// Key for the persisted theme choice (value = MeowThemeId.name).
const String kThemeSettingKey = 'theme';

/// Commands-in access to persisted key/value app settings.
abstract class SettingsStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
