# Security Policy

AI Quota reads local quota data and, for enabled providers, may request access to
macOS Keychain items or Chrome session cookies. Treat security reports involving
credential access, redirect handling, temporary files, signing, or release assets
as sensitive.

## Supported versions

The current `main` branch and the latest 1.3.x source receive security fixes.
Prebuilt beta releases are best-effort testing builds and are not notarized.

## Report a vulnerability privately

Use GitHub's private vulnerability reporting / Security Advisory flow:

https://github.com/FlyXingByte/ai-quota/security/advisories/new

Please include affected version, reproduction steps, expected impact, and a
minimal redacted diagnostic. Do **not** put API keys, OAuth tokens, Cookie values,
raw authenticated HTML, private workspace IDs, or Keychain exports in a public
Issue, Discussion, pull request, screenshot, or log.

## Disclosure

Please allow reasonable time for triage and a fix before public disclosure. If a
credential may have been exposed, revoke or rotate it through the provider first;
do not send the credential to this repository's maintainers.
