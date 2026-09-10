# Changelog

All notable changes to agent-box are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases use [Semantic Versioning](https://semver.org/).

## [0.1.2] - 2026-09-08

- Released on [Github abraxarion repository](https://github.com/abraxarion/agent-box) on 2026-09-08.

### Added

- Public repository documentation, contribution guidance, issue forms, and continuous integration.
- Project icon and refreshed README presentation.
- Regression coverage for harmless Git arguments named `push`, verbose pushes, and option-prefixed or long alias chains.
- Regression coverage for private Git snapshot permissions.
- Regression coverage for Bubblewrap executable paths containing spaces.

### Changed

- CLI help now makes the default interactive shell and optional Claude Code launch explicit.
- Git push-policy parsing now distinguishes the Git subcommand from revisions and paths.
- Git aliases resolving to `push` or `send-pack` are blocked even when they prepend global options or use long chains, while global help requests remain available.
- Git metadata snapshots are created with mode `0600`, independent of the caller's umask.
- Runtime Git policy files are staged outside caller-controlled `TMPDIR`.
- The repository bind follows private runtime mounts, preserving repositories below `/tmp`.
- The system checker enforces the documented Bash, Python, Git, and Bubblewrap minimum versions.
- Bubblewrap version detection preserves executable paths containing spaces.
- Fixed GitHub Actions CI so the release workflow runs successfully and publishes the project.
- Removed repository-local Claude workflow bundles and obsolete internal planning documents from the public package.

## [0.1.2] - 2026-09-08

- GitHub CI error fix.

## [0.1.1] - 2026-09-06

### Added

- Optional disk-backed private `/tmp` with automatic cleanup.
- Bubblewrap 0.12.0 security floor.
- Default interactive shell with optional `--claude` launch.

### Changed

- Renamed the project to agent-box.

## [0.1.0] - 2026-09-06

### Added

- Bubblewrap launcher with a read-only host root, disposable HOME overlay, and one writable repository.
- Atomic pre-launch Git metadata snapshots.
- Default Git push guard and optional offline mode.
- Bash integration tests and security documentation.

[Unreleased]: https://github.com/abraxarion/agent-box/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/abraxarion/agent-box/releases/tag/v0.1.2
[0.1.1]: https://github.com/abraxarion/agent-box/releases/tag/v0.1.1
[0.1.0]: https://github.com/abraxarion/agent-box/releases/tag/v0.1.0
