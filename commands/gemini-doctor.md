---
description: Diagnose whether the Gemini MCP server and the subagent grounding path are working in this session
allowed-tools: Read, Bash, ToolSearch
argument-hint: (no arguments)
---

You are running the /gemini-plugin:gemini-doctor slash command. Your job is to
diagnose, with EVIDENCE, whether Gemini grounding actually works in THIS session,
and to distinguish a real outage from a stale session that needs a restart.

Run all four checks below, then print the summary table. Do not skip a check
because an earlier one failed; each is independent diagnostic signal.

## Check 1: API key configured

Read the API key presence WITHOUT printing the key itself. Run:

```
test -n "${CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY:-}${GEMINI_API_KEY:-}" && echo "key: present" || echo "key: MISSING"
```

PASS if "key: present". If MISSING, the user has not configured the API key
(re-run plugin install, or set it in plugin config).

## Check 2: MCP server reachable from the MAIN agent

Use ToolSearch with the query
`select:mcp__plugin_gemini-plugin_gemini__gemini_search_grounded` to load the
tool schema. If that returns no match, also try
`select:mcp__gemini__gemini_search_grounded` (the namespace used for a manual,
non-plugin install).

- PASS if either tool schema loads. Record the exact tool name that matched;
  call this RESOLVED_TOOL.
- FAIL if neither loads (the MCP server is not registered in this session).

If a tool resolved, CALL it once with a trivial query (parameter is `prompt`),
for example `{"prompt": "what is the current stable Node.js LTS version"}`.

- PASS if it returns real results with citation URLs.
- FAIL if the call errors (server registered but not responding, for example a
  bad API key or the uvx process failing to start).

## Check 3: Subagent grounding path (THE important one)

This is the check that catches the stale-session bug: the main agent can reach
the MCP server, but the gemini-researcher subagent loaded at session start has
an outdated definition and cannot.

Spawn @agent-gemini-plugin:gemini-researcher with this exact task:

```
DIAGNOSTIC: Report the exact names of every tool in your inventory whose name
contains "gemini" or "search". Then, if you have a grounded-search tool, call it
with the query "current stable Node.js LTS version" and report whether it
returned real URLs. Return your JSON verdict with the resolved tool name in the
reasoning field, or "NO GEMINI TOOL IN INVENTORY" if you have none.
```

Block until the researcher returns. Then judge:

- PASS if the researcher reports a Gemini search tool in its inventory AND its
  verdict confidence is NOT "unavailable" (it grounded for real).
- FAIL if the researcher reports "NO GEMINI TOOL IN INVENTORY" or returns
  confidence "unavailable".

## Check 4: Installed version on disk

Run:

```
cat "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | grep '"version"' || echo "version: unknown"
```

Report the on-disk plugin version. This is the version the NEXT fresh session
will load, which may differ from what this session is running in memory.

## Summary and diagnosis

Print a table:

```
Gemini Plugin Doctor
--------------------------------------------
1. API key configured        PASS | FAIL
2. MCP server (main agent)    PASS | FAIL   (resolved tool: <name or none>)
3. Subagent grounding path    PASS | FAIL
4. On-disk version            <version>
--------------------------------------------
```

Then give ONE clear diagnosis, choosing the first that matches:

- Check 1 FAIL: "Gemini API key is not configured. Set it in the plugin
  config (re-run the install, or set GEMINI_API_KEY)."
- Check 2 FAIL (key present): "The Gemini MCP server is not reachable. The uvx
  process may be failing to start, or the API key may be rejected. Check that
  `uv` is installed and the key is valid."
- Check 2 PASS but Check 3 FAIL: "STALE SESSION. The MCP server works, but the
  gemini-researcher subagent in this session was loaded from an outdated plugin
  definition and cannot see the Gemini tools. Restart Claude Code to load the
  current agents (on-disk version is shown in check 4). This is the most common
  cause of 'grounding produced nothing' reports."
- All of 1, 2, 3 PASS: "Healthy. Gemini grounding works in this session, in both
  the main agent and the subagent path."

Be precise and factual. Report what the checks actually returned; do not claim a
PASS you did not observe.
