# Contributing

Thanks for helping improve AI Quota. Keep changes small, reviewable, and local-first.

## Development setup

Requirements:

- Apple Silicon Mac
- macOS 14+
- Command Line Tools

```bash
git clone https://github.com/FlyXingByte/ai-quota.git
cd ai-quota
./build.sh
"build/AI Quota.app/Contents/MacOS/AIQuota" --self-test
```

## Before opening a pull request

```bash
bash -n build.sh install.sh make-signing-cert.sh scripts/*.sh
git diff --check
./scripts/check-localization.sh
swiftc -typecheck -target arm64-apple-macosx14.0 -strict-concurrency=complete Sources/*.swift
./build.sh
"build/AI Quota.app/Contents/MacOS/AIQuota" --self-test
codesign --verify --deep --strict "build/AI Quota.app"
```

The same steps run in CI (`.github/workflows/ci.yml`).

For release-related changes, also run:

```bash
./scripts/create-release.sh <version>
./scripts/verify-release.sh <version>
```

## Interface text

Every user-facing string goes through `L("some.key")` and must be defined in both
`Resources/en.lproj/Localizable.strings` and `Resources/zh-Hans.lproj/Localizable.strings`.
`scripts/check-localization.sh` fails the build on a key that is missing from a
table or on a table entry nothing references, and `--self-test` checks that the
two tables define the same keys in the built bundle.

Diagnostic output — `--probe`, `--dump`, `last-refresh.log`, `last-launch.log` —
stays English-only on purpose: it is what gets pasted into an issue.

## Credential and privacy rules

- Never commit `config.json`, `.env`, Keychain exports, Cookie databases, raw
  authenticated dumps, API keys, OAuth tokens, private keys, or real workspace IDs.
- Never print or log credential values. Error messages may name a Keychain item,
  but must not include its contents.
- Prefer official, read-only provider APIs. Document any scraping or credential
  reuse clearly and keep redirects, temporary files, and destination hosts bounded.
- New providers must be optional and must not trigger permission prompts before
  first-run consent.
- Tests and screenshots must use synthetic values only.

## Pull requests

- Explain the user-visible change and security boundary.
- Include build/self-test results and visual evidence for UI changes.
- Keep unrelated refactors separate.
- Do not force-push over review feedback unless necessary; describe rewritten history.

## Forks and distribution

Before distributing a fork, change the `com.flyx.aiquota` Bundle ID, App name,
icons, signing identity, release links, and Keychain service names. Public binaries
should use Developer ID signing and Apple notarization.

Contributions are accepted under the repository's [MIT License](LICENSE).
