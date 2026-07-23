---
name: script-analyzer
description: Performs pre-run safety analysis of scripts to explain functionality, impact scope, and execution risks. Use when the user asks whether a script is safe, what it may change before running, or requests "分析脚本", "脚本安全", "执行前检查", "check this script before running". Do not use for ordinary code review when execution risk is not part of the request.
---

# Script Analyzer

Hybrid pre-run check for unknown scripts:

1. **Script** (`analyze.py`): coarse static scan (regex heuristics) for file/network/system ops and high-risk patterns
2. **LLM**: read the script + scan output, explain behavior, judge residual risk, recommend how/whether to run

Do not treat the script alone as a full security audit. It can miss obfuscation, dynamic behavior, and string/heredoc edge cases.

## Quick Start

Always use the installed skill path (works from any cwd after stow):

```bash
python3 $HOME/.agents/skills/script-analyzer/scripts/analyze.py /path/to/script.sh
python3 $HOME/.agents/skills/script-analyzer/scripts/analyze.py --json /path/to/script.sh
python3 $HOME/.agents/skills/script-analyzer/scripts/analyze.py --full /path/to/script.sh
```

Examples:

```bash
python3 $HOME/.agents/skills/script-analyzer/scripts/analyze.py $HOME/.agents/skills/script-analyzer/examples/safe_script.sh
python3 $HOME/.agents/skills/script-analyzer/scripts/analyze.py $HOME/.agents/skills/script-analyzer/examples/risky_script.sh
```

## Workflow

1. **Locate the script** the user wants reviewed; do not execute it.
2. **Run `analyze.py --json`** (or default text report) and keep the output.
3. **Read the script yourself** (full file when practical).
4. **Produce a report** using the template below, combining scan hits with semantic understanding.
5. **State limitations** when confidence is low (downloaded payloads, eval/exec, heavy obfuscation).

## What the scanner covers

- Languages (heuristic): bash/zsh, python, ruby, perl
- Hits: file ops, network/package tools, system/privilege ops, a small high-risk pattern set (`curl|sh`, `chmod 777`, `rm -rf /`, `eval`, etc.)
- Output fields: `schema_version`, purpose guess, operations, dependency names, risk level, recommendations, and structured findings with line/category/severity/confidence/evidence/reason

## Report template

```markdown
## Script Analysis Report

### Summary
[One sentence]

### Functionality
- **Main purpose**:
- **Key operations**:
- **Dependencies**:

### Impact Assessment
- **Files / system / network / persistence**:

### Risk Analysis
- **Security / stability / privacy**: Low|Medium|High — reason
- **Scanner hits worth attention**: [line refs]

### Recommendations
- Safe way to proceed / backup / sandbox / alternatives

### Limits
- What static scan likely missed
```

## Risk heuristics (for LLM judgment)

- **High**: pipe-to-shell, destructive recursive deletes, hardcoded credentials/API keys, credential exfil, unexpected privilege escalation, opaque remote payloads
- **Medium**: shell profile edits, unofficial package sources, cron/persistence, broad env changes
- **Low**: read-only info, user-space reversible changes, transparent standard tooling

## Notes

- Human-oriented extras and demos live in `README.md` and `examples/`.
- Prefer JSON scan output when you need structured fields; use `--full` only if you need more hit lines.
