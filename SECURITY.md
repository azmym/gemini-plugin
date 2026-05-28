# Security Policy

## Supported versions

Only the latest minor release receives security fixes.

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✓         |
| < 0.1   | ✗         |

## Reporting a vulnerability

**Do not file a public GitHub issue for security vulnerabilities.**

If you find a security issue (such as a way to escape the destructive-command guard, leak the API key, inject untrusted content into Gemini prompts, or bypass the SubagentStop verdict handler), please report it privately:

- Email: through the repository owner's GitHub profile
- GitHub Security Advisory: open a [private security advisory](https://github.com/azmym/gemini-plugin/security/advisories/new)

Include:

- A clear description of the vulnerability
- Reproduction steps or a proof of concept
- The version affected
- Any suggested mitigation

## Response timeline

- **Acknowledgement:** within 7 days
- **Initial assessment:** within 14 days
- **Fix or mitigation plan:** within 30 days for high-severity issues

## Scope

In scope:
- Hook scripts in `hooks/` (any way to bypass blocking, leak data, or inject untrusted content)
- The `userConfig` API key flow
- Subagent definitions in `agents/` (prompt injection, tool misuse)
- The MCP server registration in `plugin.json`

Out of scope:
- Vulnerabilities in [gemini-mcp](https://github.com/azmym/gemini-mcp) itself (report there)
- Vulnerabilities in Claude Code, MCP, or Google AI Studio (report to those vendors)
- Issues that require local code execution to exploit (the user already trusts their own machine)
