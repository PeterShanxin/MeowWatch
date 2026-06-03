/// Pure decode-mode policy, split out from [MediaKitVideoCore] so it can be
/// unit-tested without a libmpv backend.
///
/// MeowWatch defaults to **hardware** video decoding (`hwdec=auto-safe`). On a
/// Snapdragon X / Adreno (Windows on ARM) machine that offloads decode to the
/// GPU's dedicated decoder — far lower CPU, battery, and heat than software
/// decode, and smoother on 4K/HEVC. `auto-safe` only enables decoders on mpv's
/// known-good whitelist and otherwise **falls back to software automatically**,
/// so non-ARM machines (Intel/AMD via d3d11va, macOS VideoToolbox, Linux
/// vaapi/nvdec) and machines with no usable HW decoder keep working unchanged.
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
/// `'no'` forces software decoding; `'auto-safe'` enables hardware decoding on
/// mpv's safe whitelist with automatic software fallback.
String resolveHwdec({required bool forceSoftware}) =>
    forceSoftware ? 'no' : 'auto-safe';

/// Whether [environment] requests forced software decoding via
/// [forceSoftwareDecodeEnvVar]. Accepts `1`, `true`, `yes`, `on`
/// (case-insensitive, whitespace-trimmed); anything else — including unset,
/// empty, `0`, and `false` — means hardware decode.
bool forceSoftwareDecodeFromEnv(Map<String, String> environment) {
  final raw = environment[forceSoftwareDecodeEnvVar]?.trim().toLowerCase();
  return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on';
}
