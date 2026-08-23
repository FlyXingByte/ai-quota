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
bash -n build.sh install.sh scripts/create-release.sh scripts/verify-release.sh
git diff --check
./build.sh
"build/AI Quota.app/Contents/MacOS/AIQuota" --self-test
codesign --verify --deep --strict "build/AI Quota.app"
```

For release-related changes, also run:

```bash
./scripts/create-release.sh <version>
./scripts/verify-release.sh <version>
```

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
