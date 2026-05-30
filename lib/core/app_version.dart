/// Single source of truth for the app version and update configuration.
///
/// Keep [appVersion] in sync with the `version:` field in pubspec.yaml.
const String appVersion = '0.1.0-alpha';

/// GitHub repository (owner/name) — used for release page links.
const String appRepo = 'PeterShanxin/MeowWatch';

/// Base URL for the Cloudflare R2 bucket hosting release assets.
///
/// The update service fetches `{updateBaseUrl}/releases/latest.json` to check
/// for new versions, and downloads zips from the asset URLs listed there.
///
/// TODO: Replace with actual R2 bucket URL once provisioned.
const String updateBaseUrl = 'https://releases.meowwatch.app';
