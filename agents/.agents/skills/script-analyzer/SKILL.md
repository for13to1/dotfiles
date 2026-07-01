---
name: script-analyzer
description: Analyzes scripts to understand their functionality, impact scope, and potential risks before execution. Use when the user says "analyze this script", "what does this script do", "is this script safe", "check this script", "review this script", "分析脚本", "脚本分析", "检查脚本", "脚本安全", or when the user wants to understand a script before running it.
---

# Script Analyzer

Analyze scripts to understand their functionality, impact scope, and potential security risks before execution.

## Purpose

Help users make informed decisions about running scripts from the internet by providing:
- Clear summary of what the script does
- Identification of system modifications and side effects
- Assessment of potential risks and security concerns
- Recommendations for safe execution

## Quick Start

### Using the Analysis Script

```bash
# Basic analysis
python3 $HOME/.agents/skills/script-analyzer/scripts/analyze.py /path/to/script.sh

# JSON format output
python3 $HOME/.agents/skills/script-analyzer/scripts/analyze.py --json /path/to/script.sh

# Detailed analysis
python3 $HOME/.agents/skills/script-analyzer/scripts/analyze.py --full /path/to/script.sh
```

### Using LLM Analysis

For more detailed analysis, provide the script content to the LLM with the prompt:
"请分析这个脚本的功能和安全性" or "Analyze this script for functionality and safety"

## Analysis Categories

### 1. Functionality Summary
- **Purpose**: What the script is designed to accomplish
- **Main operations**: Key actions performed
- **Dependencies**: External tools, libraries, or services required
- **Input/Output**: What it reads and produces

### 2. Impact Scope
- **File System Changes**:
  - Files created, modified, or deleted
  - Directories accessed or created
  - Permission changes
- **System Modifications**:
  - Package installations/removals
  - Service configurations
  - Environment variables set
  - Shell profile modifications (.bashrc, .zshrc, etc.)
- **Network Activity**:
  - External connections made
  - Data uploads/downloads
  - API calls
- **Process Operations**:
  - Services started/stopped
  - Background processes spawned
  - System calls made

### 3. Risk Assessment
- **Security Risks**:
  - Credential exposure
  - Privilege escalation
  - Data exfiltration
  - Malicious code patterns
- **Stability Risks**:
  - System configuration changes
  - Irreversible operations
  - Dependency conflicts
- **Privacy Concerns**:
  - Personal data collection
  - Telemetry/analytics
  - Tracking mechanisms

### 4. Safety Recommendations
- **Execution environment**: Suggestions for sandboxing or isolation
- **Backup recommendations**: What to backup before running
- **Monitoring suggestions**: How to observe script behavior
- **Alternative approaches**: Safer ways to achieve the same goal

## Analysis Workflow

### Step 1: Script Examination
1. **Read the script** completely to understand its flow
2. **Identify the language** (bash, python, ruby, etc.)
3. **Check for obfuscation** or suspicious patterns
4. **Look for comments** explaining functionality

### Step 2: Static Analysis
1. **Parse commands** and function calls
2. **Trace data flow** from input to output
3. **Identify external dependencies** and downloads
4. **Check for hardcoded values** (URLs, paths, credentials)

### Step 3: Impact Mapping
1. **Map file system operations** using grep for:
   - `rm`, `mv`, `cp`, `chmod`, `chown`
   - `mkdir`, `rmdir`, `touch`
   - File redirections (`>`, `>>`, `<`)
2. **Identify network operations**:
   - `curl`, `wget`, `ssh`, `scp`
   - Package managers (`apt`, `yum`, `brew`, `pip`, `npm`)
3. **Detect system modifications**:
   - `sudo`, `su`, `passwd`
   - Service management (`systemctl`, `service`, `launchctl`)
   - Shell profile edits (`.bashrc`, `.zshrc`, `.profile`)

### Step 4: Risk Evaluation
1. **Check for common vulnerabilities**:
   - Command injection points
   - Unquoted variables
   - Unsafe temporary file usage
   - Race conditions
2. **Assess privilege requirements**:
   - Does it need root/sudo?
   - What permissions are required?
3. **Evaluate data handling**:
   - Where does data come from?
   - Where does it go?
   - Is it encrypted/secure?

### Step 5: Report Generation
Provide a structured report with:
- **Summary**: One-line description of what the script does
- **Detailed Analysis**: Breakdown of each major operation
- **Impact Assessment**: What changes will be made to the system
- **Risk Level**: Low/Medium/High with justification
- **Recommendations**: How to safely proceed

## Output Format

```markdown
## Script Analysis Report

### Summary
[One-sentence description of script purpose]

### Functionality
- **Main purpose**: [What it does]
- **Key operations**: [List of major actions]
- **Dependencies**: [Required tools/libraries]

### Impact Assessment
- **Files affected**: [List of files/directories modified]
- **System changes**: [Configuration changes, installations]
- **Network activity**: [External connections made]
- **Persistence**: [Changes that survive reboot]

### Risk Analysis
- **Security risk**: [Low/Medium/High] - [Reason]
- **Stability risk**: [Low/Medium/High] - [Reason]
- **Privacy risk**: [Low/Medium/High] - [Reason]

### Recommendations
- **Safe execution**: [Suggestions for running safely]
- **Backup**: [What to backup]
- **Monitoring**: [How to observe behavior]
- **Alternatives**: [Safer approaches if applicable]

### Detailed Breakdown
[Line-by-line analysis of important sections]
```

## Common Patterns to Watch

### High-Risk Indicators
- `curl | bash` or `wget -O- | sh` (piping downloaded content to shell)
- `chmod 777` (excessive permissions)
- `rm -rf /` or similar destructive commands
- Hardcoded credentials or API keys
- Downloads from untrusted sources
- Modification of system binaries
- Changes to security settings

### Medium-Risk Indicators
- Installation of packages from unofficial sources
- Modification of shell profiles
- Creation of cron jobs or scheduled tasks
- Network services configuration
- Environment variable modifications

### Low-Risk Indicators
- Read-only operations
- User-space modifications only
- Well-documented, transparent operations
- Reversible changes
- Standard package manager usage

## Usage Examples

### Example 1: Safe Script
```bash
# Analyze a simple system info script
python3 scripts/analyze.py examples/safe_script.sh
```

**Output:**
- Risk Level: LOW
- Operations: None detected
- Recommendations: Script appears relatively safe

### Example 2: High-Risk Script
```bash
# Analyze an installation script with system modifications
python3 scripts/analyze.py examples/risky_script.sh
```

**Output:**
- Risk Level: HIGH
- Operations: File, Network, System operations detected
- Recommendations: DO NOT run without review, use sandbox environment

### Example 3: Python Script
```bash
# Analyze a Python script with various operations
python3 scripts/analyze.py examples/python_example.py
```

**Output:**
- Risk Level: HIGH
- Operations: File, Network, System operations detected
- Dependencies: requests, subprocess, shutil, etc.

### Example 4: JSON Output
```bash
# Get analysis in JSON format for further processing
python3 scripts/analyze.py --json examples/risky_script.sh
```

## Best Practices

1. **Always analyze before running** unknown scripts
2. **Run in isolated environment** when possible (VM, container, sandbox)
3. **Backup critical data** before executing system-modifying scripts
4. **Monitor execution** with tools like `strace`, `dtrace`, or process monitors
5. **Verify sources** - check script provenance and author reputation
6. **Check for updates** - newer versions may fix security issues
7. **Read reviews** - see if others have analyzed or used the script

## Limitations

- **Dynamic behavior**: Some script behavior depends on runtime conditions
- **Obfuscated code**: Heavily obfuscated scripts may be difficult to analyze
- **External dependencies**: Behavior of downloaded components may change
- **Zero-day exploits**: Novel attack patterns may not be recognized
- **Complex interactions**: Multi-script interactions may not be fully mapped
