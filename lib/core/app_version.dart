/// Single source of truth for the app version and update configuration.
///
/// Keep [appVersion] in sync with the `version:` field in pubspec.yaml.
const String appVersion = '0.7.0-alpha';

/// GitHub repository (owner/name) — used for release page links.
const String appRepo = 'PeterShanxin/MeowWatch';

/// Base URL for the Cloudflare R2 bucket hosting release assets.
///
/// The update service fetches `{updateBaseUrl}/releases/latest.json` to check
/// for new versions, and downloads zips from the asset URLs listed there.
///
/// This is the R2 public development URL. Must match the `R2_PUBLIC_URL`
/// GitHub secret used by the release workflow. Swap for a custom domain
/// (e.g. https://releases.meowwatch.app) if the bucket moves to one.
const String updateBaseUrl =
    'https://pub-6002641cc8a44c128f0684981b511991.r2.dev';
