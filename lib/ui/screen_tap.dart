/// What a single tap on the video surface should do.
///
/// A tap serves double duty: while the chat card is open it dismisses the card
/// (and leaves playback alone, so the click that closes chat never also
/// pauses); with chat closed it toggles play/pause. Kept as pure logic so the
/// decision is unit-tested headless — [VideoSurface] pulls in `media_kit`,
/// which a widget test can't easily pump.
enum ScreenTapAction {
  /// Chat is open — collapse it; do not touch playback.
  dismissChat,

  /// Chat is closed — toggle play/pause.
  togglePlay,
}

/// Resolve a video-surface tap: dismiss the chat card if it's open, otherwise
/// toggle playback.
ScreenTapAction resolveScreenTap({required bool chatOpen}) =>
    chatOpen ? ScreenTapAction.dismissChat : ScreenTapAction.togglePlay;
