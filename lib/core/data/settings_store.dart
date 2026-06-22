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

/// Key for the persisted continue-watching mode (value = a HistoryMode
/// `storageName`: `latest_per_room` / `every_video`; absent/unknown →
/// `latestPerRoom`).
const String kHistoryModeSettingKey = 'history_mode';

/// Key for the last app version the user has seen (value = an [appVersion]
/// string). Drives the one-time post-update "what's new" modal: absent → fresh
/// install (no modal); differs from the current version → the user updated.
const String kLastSeenVersionKey = 'last_seen_version';

/// Commands-in access to persisted key/value app settings.
abstract class SettingsStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}
