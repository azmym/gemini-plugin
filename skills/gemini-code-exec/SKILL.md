---
description: Run Python code in Gemini's sandboxed execution environment to verify math, test regex patterns, simulate logic, or validate algorithms without local execution. Use when you need computational verification without side effects.
---

# Gemini Code Exec

Use this skill to run Python code inside Gemini's isolated sandbox. This gives you a clean, side-effect-free execution environment for verifying computations, testing patterns, and validating logic without touching the local machine.

## When to use this skill

- **Math verification:** Confirm a formula, check a statistical calculation, or validate a numeric result.
- **Regex testing:** Test a regular expression against a set of sample inputs before embedding it in production code.
- **Algorithm simulation:** Run a sorting algorithm, dynamic programming solution, or graph traversal with sample data to verify correctness.
- **Data transformation validation:** Confirm that a proposed data mapping, normalization, or encoding produces the expected output.
- **Edge case probing:** Run code against boundary values (zero, max int, empty string, None) to see what happens.
- **Dependency-free snippets:** Execute a pure-Python snippet that has no local filesystem or network dependencies.

## MCP tools

| Tool | Purpose |
|---|---|
| `mcp__gemini__gemini_code_execute` | Submit Python code for execution in Gemini's sandbox and receive stdout, stderr, and the return value |

## Usage pattern

### Verify a math formula

```json
{
  "tool": "mcp__gemini__gemini_code_execute",
  "arguments": {
    "code": "import math\n\ndef compound_interest(principal, rate, periods):\n    return principal * (1 + rate) ** periods\n\nresult = compound_interest(1000, 0.05, 10)\nprint(f'After 10 years: {result:.2f}')"
  }
}
```

### Test a regex pattern

```json
{
  "tool": "mcp__gemini__gemini_code_execute",
  "arguments": {
    "code": "import re\n\npattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'\ntest_cases = ['user@example.com', 'bad-email', 'user@.com', 'a@b.co']\nfor case in test_cases:\n    match = bool(re.match(pattern, case))\n    print(f'{case!r}: {match}')"
  }
}
```

### Validate an algorithm

```json
{
  "tool": "mcp__gemini__gemini_code_execute",
  "arguments": {
    "code": "def longest_common_subsequence(s1, s2):\n    m, n = len(s1), len(s2)\n    dp = [[0] * (n + 1) for _ in range(m + 1)]\n    for i in range(1, m + 1):\n        for j in range(1, n + 1):\n            if s1[i-1] == s2[j-1]:\n                dp[i][j] = dp[i-1][j-1] + 1\n            else:\n                dp[i][j] = max(dp[i-1][j], dp[i][j-1])\n    return dp[m][n]\n\nprint(longest_common_subsequence('ABCBDAB', 'BDCAB'))  # Expected: 4"
  }
}
```

## Sandbox constraints

- The sandbox runs Python only (no Bash, no Node, no compiled binaries).
- No network access: do not attempt to `import requests` or call external APIs.
- No filesystem writes: the sandbox is read-only with respect to persistent storage.
- Standard library modules are available; most common data-science packages (numpy, pandas, etc.) may also be available, but verify availability before relying on them.
- Execution time is bounded; avoid infinite loops or very long-running computations.

## Tips

- Keep the code self-contained. Pass all required data as literals in the snippet.
- Use `print()` extensively; the tool returns stdout as the primary result.
- If you need to test multiple cases, loop over them in a single submission rather than making multiple tool calls.
- Always present the output to the user alongside the code so they can verify the result independently.

## Do NOT use this skill for

- Running code that has filesystem side effects (file writes, deletes) on the local machine.
- Executing non-Python languages (Bash, JavaScript, Ruby, Go).
- Code that needs network access or calls to external services.
- Code generation without execution (use `gemini-chat-and-reason` for pure code review).
- Tasks that do not require execution at all, where static analysis is sufficient.
