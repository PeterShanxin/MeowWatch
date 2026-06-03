/// Pure decode-mode policy, split out from [MediaKitVideoCore] so it can be
/// unit-tested without a libmpv backend.
///
/// MeowWatch defaults to **hardware** video decoding. On **Windows** (our
/// primary target, incl. Snapdragon X / Adreno) we ask for `hwdec=d3d11va`
/// specifically — the **zero-copy** D3D11VA path that keeps decoded frames in
/// GPU memory and hands them straight to media_kit's ANGLE/D3D11 texture path,
/// avoiding the GPU→RAM→GPU copy-back round-trip `auto-safe` might otherwise
/// pick. That saves memory bandwidth and power, which matters most on
/// Adreno's unified-memory architecture. mpv falls back to software decoding
/// on its own if d3d11va can't initialise (no usable decoder), so the failure
/// mode stays "plays in software", never a hard error.
///
/// On every other platform we keep `hwdec=auto-safe`: it only enables decoders
/// on mpv's known-good whitelist (macOS VideoToolbox, Linux vaapi/nvdec) and
/// otherwise falls back to software automatically.
///
/// Software decode can still be forced via the [forceSoftwareDecodeEnvVar]
/// environment variable. The one case that needs it: running **two app
/// instances on a single PC** for local sync testing — they contend for the
/// single hardware decoder session and the second one stalls at frame 0. Real
/// two-machine use has one decoder per machine and never needs this.
library;

/// Environment variable that, when truthy, forces software video decoding.
///
/// Set it before launching for two-instance-on-one-PC manual testing, e.g.
/// PowerShell: `$env:MEOWWATCH_FORCE_SW_DECODE = '1'`.
const String forceSoftwareDecodeEnvVar = 'MEOWWATCH_FORCE_SW_DECODE';

/// The mpv `hwdec` property value for the chosen decode mode.
///
/// - [forceSoftware] true → `'no'` (software decode; the two-instance test path).
/// - Windows hardware path → `'d3d11va'`, the zero-copy D3D11VA decoder that
///   stays in GPU memory for media_kit's texture path (auto-falls back to
///   software inside mpv if d3d11va is unavailable).
/// - Every other platform → `'auto-safe'`, hardware decode on mpv's safe
///   whitelist with automatic software fallback.
String resolveHwdec({required bool forceSoftware, required bool isWindows}) {
  if (forceSoftware) return 'no';
  return isWindows ? 'd3d11va' : 'auto-safe';
}

/// Whether [environment] requests forced software decoding via
/// [forceSoftwareDecodeEnvVar]. Accepts `1`, `true`, `yes`, `on`
/// (case-insensitive, whitespace-trimmed); anything else — including unset,
/// empty, `0`, and `false` — means hardware decode.
bool forceSoftwareDecodeFromEnv(Map<String, String> environment) {
  final raw = environment[forceSoftwareDecodeEnvVar]?.trim().toLowerCase();
  return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on';
}
