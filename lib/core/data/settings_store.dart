/// Key for the persisted theme choice (value = MeowThemeId.name).
const String kThemeSettingKey = 'theme';

/// Key for the persisted chat-card size (value = `"<widthPx>,<heightPx>"`,
/// or empty string for the default size).
const String kChatCardSizeSettingKey = 'chat_card_size';

/// Key for the persisted choice to auto-dim the expanded chat card on idle
/// (value = "true" or "false", default = "true").
const String kChatAutoDimSettingKey = 'chat_auto_dim';

/// Commands-in access to persisted key/value app settings.
abstract class SettingsStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
