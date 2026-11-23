/// App configuration.
///
/// Nothing secret or personal is committed. Supply values at build time:
///   flutter run --dart-define-from-file=env.json
/// where env.json is an untracked copy of env.example.json (gitignored), or
/// pass individual --dart-define=GITHUB_TOKEN=... / GITHUB_OWNER / GITHUB_REPO.
///
/// A client-side token always ends up inside the built binary. Use a
/// fine-grained token scoped to the data repo only. The durable fix is a real
/// backend with per-user auth.
const String _envToken = String.fromEnvironment('GITHUB_TOKEN');

/// Intentionally empty: tokens are never committed.
const String _fallbackToken = '';

/// Public-demo build switch (`--dart-define=CALCETTO_DEMO=true`). When on, the
/// app talks to an in-memory placeholder backend (lib/demo/demo_backend.dart):
/// no token and no data-repo name is compiled into the build.
const bool kDemoMode = bool.fromEnvironment('CALCETTO_DEMO');

const String kGithubToken = kDemoMode
    ? ''
    : (_envToken != '' ? _envToken : _fallbackToken);

const String kGithubOwner = kDemoMode
    ? 'demo'
    : String.fromEnvironment('GITHUB_OWNER', defaultValue: 'your-github-user');
const String kGithubRepo = kDemoMode
    ? 'demo'
    : String.fromEnvironment('GITHUB_REPO', defaultValue: 'your-data-repo');
const String kGithubBaseUrl =
    'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/contents/';

/// The only user allowed to access admin tooling and edit real results.
const String kAdminUser = 'Admin';

bool isAdminUser(String? username) =>
    username != null && username.toLowerCase() == kAdminUser.toLowerCase();

const int kTotalSquadSize = 11;
const int kTotalBenchSize = 5;
