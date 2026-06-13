/// Key for the persisted theme choice (value = MeowThemeId.name).
const String kThemeSettingKey = 'theme';

/// Key for the persisted chat-card size (value = `"<widthPx>,<heightPx>"`,
/// or empty string for the default size).
const String kChatCardSizeSettingKey = 'chat_card_size';

/// Key for the persisted choice to auto-dim the expanded chat card on idle
/// (value = "true" or "false", default = "true").
const String kChatAutoDimSettingKey = 'chat_auto_dim';

/// Key for the persisted choice to fully wake the chat card when a new
/// message arrives during idle (value = "true" or "false", default = "false").
const String kChatWakeOnNewMessageSettingKey = 'chat_wake_on_new_message';

/// Key for the persisted opacity of the dimmed (idle, not-deep) chat card
/// (value = a double in `[kChatIdleDimMin, kChatIdleDimMax]` as a string,
/// default = `kChatIdleGhostOpacity`). Lets the user tune how readable the
/// dimmed chat stays.
const String kChatIdleDimSettingKey = 'chat_idle_dim';

/// Key for the persisted primary notification sound (value = a NotifySound id
/// from `kPrimarySounds`; absent/unknown → `kDefaultPrimarySoundId`).
const String kNotifyPrimarySoundKey = 'notify_primary_sound';

/// Key for the persisted secondary (quiet) notification sound (value = a
/// NotifySound id from `kSecondarySounds`; absent/unknown → default).
const String kNotifySecondarySoundKey = 'notify_secondary_sound';

/// Key for the persisted diagnostic log verbosity (value = a LogLevel
/// `storageName`: `off` / `neat` / `verbose`; absent/unknown → `verbose`).
const String kLogLevelSettingKey = 'log_level';

/// Key for the one-time "press Tab to show/hide chat" load-screen hint
/// (value = "true" once shown; absent → not yet shown). Keeps the guide a
/// one-time nudge instead of nagging on every load screen.
const String kChatTabHintSeenKey = 'chat_tab_hint_seen';

/// Commands-in access to persisted key/value app settings.
abstract class SettingsStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
