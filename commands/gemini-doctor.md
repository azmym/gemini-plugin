---
description: Diagnose whether the Gemini MCP server and the subagent grounding path are working in this session
allowed-tools: Read, Bash, ToolSearch, Task, Agent
argument-hint: (no arguments)
---

You are running the /gemini-plugin:gemini-doctor slash command. Your job is to
diagnose, with EVIDENCE, whether Gemini grounding actually works in THIS session,
and to distinguish a real outage from a check that could not be run.

## The reporting contract (read this first)

This command is a diagnostic. A diagnostic that reports a result it did not
observe is worse than no diagnostic at all, because it sends the reader off to
fix the wrong thing. Three rules, and they override everything else in this file:

1. **Every check reports one of three verdicts: PASS, FAIL, or INCONCLUSIVE.**
   PASS and FAIL both mean "the check ran and I saw the outcome". INCONCLUSIVE
   means "the check did not run, or ran in a way that tells me nothing".
2. **Every check prints an `Evidence:` line** holding the raw thing you observed:
   the exact tool name the host returned, the exact command output, the exact
   error text. Copy it verbatim. Never write a tool name, version, or namespace
   from memory, from this file, or from what you expected to see. If you cannot
   quote it, you did not observe it.
3. **A verdict without evidence is forbidden.** If you have no evidence line,
   the verdict is INCONCLUSIVE. Do not guess, do not infer a verdict from a
   sibling check, and do not smooth over a gap to make the table look complete.

Host portability matters here too. This plugin runs under more than one agent
harness, and harnesses differ in tool names, MCP namespaces, and how subagents
are spawned. Never assume a specific harness. Where a check below names a
mechanism, treat it as an example and use whatever this host actually provides.

Run all four checks. Do not skip a check because an earlier one failed; each is
independent diagnostic signal.

## Check 1: API key configured

Read the API key presence WITHOUT printing the key itself. Run:

```
test -n "${CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY:-}${GEMINI_API_KEY:-}" && echo "key: present" || echo "key: MISSING"
```

- PASS if the output is "key: present".
- FAIL if the output is "key: MISSING". The user has not configured the API key
  (re-run the plugin install, or set GEMINI_API_KEY).
- INCONCLUSIVE if the command could not be run at all.

`Evidence:` the literal line the command printed.

## Check 2: MCP server reachable from the MAIN agent

Resolve the grounded-search tool WITHOUT assuming a namespace. The MCP prefix
differs per host and per install type (plugin install versus manual install), so
a hardcoded full tool path is guaranteed to be wrong somewhere. Match on the
tool name suffix `gemini_search_grounded` and accept any prefix.

Resolve in this order:

1. If this host provides a tool-schema search facility (for example a
   `ToolSearch` tool), query it with a keyword query such as
   `gemini search grounded`, then use the exact tool name it returns.
2. If it does not, the MCP tools are loaded directly. Find the tool in your own
   inventory whose name ends in `gemini_search_grounded`.

Then judge:

- FAIL if no tool matching that suffix exists. The MCP server is not registered
  in this session.
- INCONCLUSIVE if you can neither enumerate your own tools nor query a search
  facility, because then you cannot tell a missing tool from an inability to
  look for one.

If a tool resolved, record its full name verbatim as RESOLVED_TOOL, then CALL it
once with a trivial query (the parameter is `prompt`), for example
`{"prompt": "what is the current stable Node.js LTS version"}`.

- PASS if it returns real results with citation URLs.
- FAIL if the call errors (server registered but not responding, for example a
  rejected API key, or a uvx process that fails to start).

`Evidence:` RESOLVED_TOOL copied character for character from what the host
returned, plus either one citation URL from the response or the verbatim error
text. If the name you are about to write did not come from the host's own
output, stop: the verdict is INCONCLUSIVE.

## Check 3: Subagent grounding path

This check exists to catch one specific failure: the main agent can reach the
MCP server, but the gemini-researcher subagent cannot. Spawn the
gemini-researcher subagent using whatever mechanism this host provides (an agent
mention, a task tool, or an agent tool) with this exact task:

```
DIAGNOSTIC: Report the exact names of every tool in your inventory whose name
contains "gemini" or "search". Then, if you have a grounded-search tool, call it
with the query "current stable Node.js LTS version" and report whether it
returned real URLs. Return your JSON verdict with the resolved tool name in the
reasoning field, or "NO GEMINI TOOL IN INVENTORY" if you have none.
```

Block until the researcher returns, then judge. Separate "the subagent ran and
failed" from "the subagent never ran". Those two look similar in a transcript
and mean opposite things:

- PASS if the researcher reports a Gemini search tool in its inventory AND its
  verdict confidence is not "unavailable", meaning it grounded for real.
- FAIL if the researcher RAN and reported "NO GEMINI TOOL IN INVENTORY", or
  returned confidence "unavailable". The subagent path is genuinely broken.
- INCONCLUSIVE if the spawn itself did not complete: the agent is not registered
  under this host, the prompt was rejected (for example "prompt is too long"),
  the harness errored, the turn budget ran out, or nothing came back. This says
  NOTHING about grounding. A spawn that never ran is not evidence that grounding
  is broken, and must never be reported as FAIL.

`Evidence:` on PASS or FAIL, the resolved tool name and the confidence value the
researcher reported. On INCONCLUSIVE, the verbatim spawn error text.

## Check 4: Installed version on disk

The plugin copy loaded by the session and a working copy on disk can be
different versions, so report WHICH FILE you read, not just a number. Run:

```
found=$(for f in "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/.claude-plugin/plugin.json" \
                 "$HOME"/.claude/plugins/gemini-plugin/.claude-plugin/plugin.json \
                 "$HOME"/.claude/plugins/*/gemini-plugin/.claude-plugin/plugin.json \
                 "$HOME"/.kimi-code/plugins/*/gemini-plugin/.claude-plugin/plugin.json \
                 "$PWD/.claude-plugin/plugin.json"; do
  [ -f "$f" ] || continue
  v=$(grep '"version"' "$f" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  echo "${v:-unparsed}  <-  $f"
done | sort -u)
[ -n "$found" ] && echo "$found" || echo "version: unknown"
```

Report every path found together with its version.

- If exactly one version is found, report it as the on-disk version, naming the
  path it came from.
- If two or more DIFFERENT versions are found, report VERSION DRIFT and name
  both paths. An installed copy older than a working copy explains a session
  that behaves unlike the source you are reading.
- INCONCLUSIVE if no plugin.json was found ("version: unknown"). Say so plainly
  rather than reporting the version of whatever directory you happen to be in.

`Evidence:` the raw lines the command printed.

## Summary and diagnosis

Print a table, using only the verdicts you actually recorded:

```
Gemini Plugin Doctor
--------------------------------------------
1. API key configured        PASS | FAIL | INCONCLUSIVE
2. MCP server (main agent)    PASS | FAIL | INCONCLUSIVE   (resolved tool: <verbatim name, or none>)
3. Subagent grounding path    PASS | FAIL | INCONCLUSIVE
4. On-disk version            <version and path, or DRIFT, or unknown>
--------------------------------------------
```

Below the table, reproduce each check's `Evidence:` line, so the reader can
check every verdict against what was actually observed.

Then give ONE diagnosis, choosing the first that matches:

- Check 1 FAIL: "Gemini API key is not configured. Set it in the plugin config
  (re-run the install, or set GEMINI_API_KEY)."
- Check 2 FAIL with the key present: "The Gemini MCP server is not reachable.
  The uvx process may be failing to start, or the API key may be rejected. Check
  that `uv` is installed and the key is valid."
- Check 2 PASS and check 3 FAIL: "STALE SESSION. The MCP server works, but the
  gemini-researcher subagent in this session was loaded from an outdated plugin
  definition and cannot see the Gemini tools. Restart the session to load the
  current agents (compare the on-disk version from check 4). This is the most
  common cause of 'grounding produced nothing' reports." Claim this ONLY when
  check 3 is a genuine FAIL, meaning the researcher ran and reported no tool.
  Never claim a stale session when check 3 is INCONCLUSIVE.
- Any check INCONCLUSIVE: name the check that could not be determined, quote the
  reason, and state what would settle it. For example: "Check 3 could not run
  because the spawn was rejected. Subagent grounding is UNKNOWN, not broken.
  Re-run in a fresh session to determine it." Then report the checks that did
  complete, on their own evidence.
- Checks 1, 2 and 3 all PASS: "Healthy. Gemini grounding works in this session,
  in both the main agent and the subagent path."

Be precise and factual. Report what the checks actually returned. Do not claim a
PASS you did not observe, do not report FAIL for a check that never ran, and do
not print a tool name or version you did not read from real output.
