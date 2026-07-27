# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅        |

## Architecture

Autohand Voice is designed with security as a first principle:

- **100% local processing** — no audio or text leaves your machine
- **No network calls** except to localhost LLM endpoints and optional update checks
- **Model repository allowlist** — only `mlx-community/` prefixed models accepted
- **No telemetry, no analytics, no tracking**
- **Clipboard access** is the only system integration (required for auto-paste)

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public issue**
2. Open a [private security advisory](https://github.com/autohandai/voice/security/advisories/new) on GitHub
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will acknowledge receipt within 48 hours and aim to release a fix within 7 days for critical issues.

Upstream security history is retained in the Git history and original project.

## Scope

The following are **in scope**:
- Code execution via crafted input
- Model loading from unauthorized sources
- Clipboard data leaks
- Privilege escalation

The following are **out of scope**:
- Physical access attacks
- Accessibility permission abuse (macOS system-level)
- Attacks requiring modifying the installed package
