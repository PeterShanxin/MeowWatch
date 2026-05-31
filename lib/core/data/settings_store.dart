/// Key for the persisted theme choice (value = MeowThemeId.name).
const String kThemeSettingKey = 'theme';

/// Key for the persisted chat-card size (value = `"<widthPx>,<heightPx>"`,
/// or empty string for the default size).
const String kChatCardSizeSettingKey = 'chat_card_size';

/// Commands-in access to persisted key/value app settings.
abstract class SettingsStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
