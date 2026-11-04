# Security

## Reporting vulnerabilities

Do not post exploit details, API keys, or sensitive captures in public issues. Use
**Security → Report a vulnerability** on the GitHub repository if private vulnerability
reporting is enabled. Include the affected commit/version, impact, reproduction steps,
and a minimal example using synthetic data.

If private reporting is unavailable, open an issue requesting a private reporting channel
without vulnerability details, and wait for the maintainer to arrange one.

Fixes are made on the current development branch. There is no commitment to maintain older
versions or a guaranteed response time.

## Sensitive data

The OpenRouter key belongs only in macOS Keychain. Do not attach real keys, private documents,
or unsanitized snapshots to reports. Revoke exposed keys with the provider; deleting them from
a file does not invalidate them or remove them from Git history.

AI features send selection content and conversation context through OpenRouter. Agent input
uses Accessibility and has approval enabled by default. Approval bypasses, key disclosure,
or unexpected capture/transmission of content should be reported privately.
