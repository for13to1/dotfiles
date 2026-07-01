#!/usr/bin/env python3
"""
Script Analyzer - Static analysis tool for scripts
Analyzes scripts for functionality, impact, and potential risks
"""

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from enum import Enum
from pathlib import Path


class RiskLevel(Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


@dataclass
class AnalysisResult:
    script_path: str
    language: str
    purpose: str
    operations: list[str]
    file_operations: list[str]
    network_operations: list[str]
    system_operations: list[str]
    dependencies: list[str]
    risk_level: str
    risk_factors: list[str]
    recommendations: list[str]


# Pattern definitions for different script languages
PATTERNS = {
    "bash": {
        "file_ops": [
            r"\brm\b",
            r"\bmv\b",
            r"\bcp\b",
            r"\bchmod\b",
            r"\bchown\b",
            r"\bmkdir\b",
            r"\brmdir\b",
            r"\btouch\b",
            r"\bcat\b.*>",
            r"\btee\b",
            r"\bsed\b.*-i",
            r"\bawk\b.*>",
            r"\bfind\b.*-delete",
            r"\bshred\b",
        ],
        "network_ops": [
            r"\bcurl\b",
            r"\bwget\b",
            r"\bssh\b",
            r"\bscp\b",
            r"\brsync\b",
            r"\bnc\b",
            r"\bnetcat\b",
            r"\bnmap\b",
            r"\bping\b",
            r"\bapt\b",
            r"\byum\b",
            r"\bbrew\b",
            r"\bpip\b",
            r"\bnpm\b",
        ],
        "system_ops": [
            r"\bsudo\b",
            r"\bsu\b",
            r"\bpasswd\b",
            r"\bsystemctl\b",
            r"\bservice\b",
            r"\blaunchctl\b",
            r"\bcrontab\b",
            r"\bmount\b",
            r"\bumount\b",
            r"\bfsck\b",
            r"\bkill\b",
            r"\bpkill\b",
            r"\bkillall\b",
        ],
        "dangerous": [r"chmod\s+777", r"chmod\s+\+s", r"rm\s+-rf\s+/", r"mkfs", r"dd\s+if=", r":(){ :\|:& };:"],
    },
    "python": {
        "file_ops": [
            r"\bopen\s*\(",
            r"\bos\.remove\b",
            r"\bos\.unlink\b",
            r"\bos\.rename\b",
            r"\bshutil\.(move|copy|copytree|rmtree)\b",
            r"\bos\.makedirs\b",
            r"\bos\.mkdir\b",
            r"\bos\.rmdir\b",
            r"\bos\.chmod\b",
            r"\bos\.chown\b",
        ],
        "network_ops": [
            r"\brequests\.(get|post|put|delete)\b",
            r"\burllib\b",
            r"\bsocket\b",
            r"\bhttp\.client\b",
            r"\bftplib\b",
            r"\bsmtplib\b",
            r"\bparamiko\b",
            r"\bhttpx\b",
        ],
        "system_ops": [
            r"\bos\.system\b",
            r"\bsubprocess\.(run|call|Popen)\b",
            r"\bos\.exec\b",
            r"\bos\.spawn\b",
            r"\bos\.popen\b",
            r"\bos\.environ\b",
            r"\bsys\.exit\b",
        ],
        "dangerous": [
            r"\beval\s*\(",
            r"\bexec\s*\(",
            r"__import__\s*\(",
            r'\bos\.system\s*\(\s*["\']rm',
            r"subprocess.*shell\s*=\s*True",
        ],
    },
    "ruby": {
        "file_ops": [r"\bFile\.(delete|unlink|rename|chmod|chown)\b", r"\bDir\.(mkdir|rmdir|glob)\b", r"\bFileUtils\b"],
        "network_ops": [r"\bNet::HTTP\b", r"\bopen-uri\b", r"\bcurl\b", r"\bRESTClient\b", r"\bhttparty\b"],
        "system_ops": [r"\bsystem\s*\(", r"\bexec\s*\(", r"\b`.*`\b", r"\bProcess\.(fork|spawn)\b", r"\bIO\.popen\b"],
        "dangerous": [r"\beval\s*\(", r"\bsend\s*\(", r"\binstance_eval\b", r'\bsystem\s*\(\s*["\']rm'],
    },
    "perl": {
        "file_ops": [
            r"\bunlink\b",
            r"\brename\b",
            r"\bchmod\b",
            r"\bchown\b",
            r"\bmkdir\b",
            r"\brmdir\b",
            r"\bopen\b.*>",
        ],
        "network_ops": [r"\bLWP::UserAgent\b", r"\bIO::Socket\b", r"\bHTTP::Request\b"],
        "system_ops": [r"\bsystem\s*\(", r"\bexec\s*\(", r"\b`.*`\b", r"\bopen\s*\|\s*-", r"\bfork\b"],
        "dangerous": [r"\beval\s*\(", r"\bexec\s*\(", r'system\s*\(\s*["\']rm'],
    },
}

# High-risk patterns across all languages
HIGH_RISK_PATTERNS = [
    r"curl.*\|\s*(ba)?sh",  # Pipe to shell
    r"wget.*\|\s*(ba)?sh",  # Pipe to shell
    r"rm\s+-rf\s+/",  # Recursive delete from root
    r"chmod\s+777",  # World-writable
    r"chmod\s+\+s",  # Setuid/setgid
    r"eval\s*\(",  # Code evaluation
    r"exec\s*\(",  # Code execution
    r":(){ :\|:& };:",  # Fork bomb
    r"dd\s+if=.*of=/dev/",  # Direct disk write
    r"mkfs",  # Format filesystem
    r">\s*/dev/sd",  # Direct device write
]


def detect_language(script_path: str) -> str:
    """Detect script language from shebang or extension"""
    path = Path(script_path)

    # Check shebang
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            first_line = f.readline().strip()
            if first_line.startswith("#!"):
                if "python" in first_line:
                    return "python"
                elif "ruby" in first_line:
                    return "ruby"
                elif "perl" in first_line:
                    return "perl"
                elif "bash" in first_line or "sh" in first_line:
                    return "bash"
    except Exception:
        pass

    # Check extension
    ext = path.suffix.lower()
    ext_map = {".py": "python", ".rb": "ruby", ".pl": "perl", ".sh": "bash", ".bash": "bash", ".zsh": "bash"}

    return ext_map.get(ext, "bash")  # Default to bash


def analyze_patterns(content: str, language: str) -> dict[str, list[str]]:
    """Analyze script content for specific patterns"""
    patterns = PATTERNS.get(language, PATTERNS["bash"])
    results: dict[str, list[str]] = {"file_ops": [], "network_ops": [], "system_ops": [], "dangerous": []}

    lines = content.split("\n")

    for line_num, line in enumerate(lines, 1):
        # Skip comments
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("//"):
            continue

        for category, pattern_list in patterns.items():
            for pattern in pattern_list:
                if re.search(pattern, line, re.IGNORECASE):
                    results[category].append(f"Line {line_num}: {stripped[:80]}")
                    break

    return results


def detect_high_risk(content: str) -> list[str]:
    """Detect high-risk patterns"""
    risks = []
    lines = content.split("\n")

    for line_num, line in enumerate(lines, 1):
        for pattern in HIGH_RISK_PATTERNS:
            if re.search(pattern, line, re.IGNORECASE):
                risks.append(f"Line {line_num}: {line.strip()[:80]}")
                break

    return risks


def extract_dependencies(content: str, language: str) -> list[str]:
    """Extract dependencies from script"""
    deps = []

    if language == "python":
        # Python imports
        import_patterns = [r"^import\s+(\w+)", r"^from\s+(\w+)\s+import", r"^from\s+(\w+)\.\w+\s+import"]
        for pattern in import_patterns:
            matches = re.findall(pattern, content, re.MULTILINE)
            deps.extend(matches)

    elif language == "bash":
        # Check for common tools used
        tools = ["curl", "wget", "git", "docker", "python", "node", "npm", "pip"]
        for tool in tools:
            if re.search(rf"\b{tool}\b", content):
                deps.append(tool)

    elif language == "ruby":
        # Ruby requires
        matches = re.findall(r"require\s+['\"](\w+)['\"]", content)
        deps.extend(matches)

    elif language == "perl":
        # Perl modules
        matches = re.findall(r"use\s+(\w+)", content)
        deps.extend(matches)

    return list(set(deps))


def assess_risk(analysis: dict) -> tuple[RiskLevel, list[str]]:
    """Assess overall risk level"""
    risk_factors = []
    risk_score = 0

    # Check for dangerous patterns
    if analysis["dangerous"]:
        risk_score += 3
        risk_factors.append("Contains dangerous patterns")

    # Check for system operations
    if analysis["system_ops"]:
        risk_score += 2
        risk_factors.append("Performs system operations")

    # Check for network operations
    if analysis["network_ops"]:
        risk_score += 1
        risk_factors.append("Makes network connections")

    # Check for file operations
    if analysis["file_ops"]:
        risk_score += 1
        risk_factors.append("Modifies files")

    # Determine risk level
    if risk_score >= 4:
        return RiskLevel.HIGH, risk_factors
    elif risk_score >= 2:
        return RiskLevel.MEDIUM, risk_factors
    else:
        return RiskLevel.LOW, risk_factors


def generate_recommendations(risk_level: RiskLevel, analysis: dict) -> list[str]:
    """Generate safety recommendations"""
    recommendations = []

    if risk_level == RiskLevel.HIGH:
        recommendations.extend(
            [
                "DO NOT run this script without thorough review",
                "Consider running in a sandboxed environment (VM, container)",
                "Backup all important data before execution",
                "Monitor system behavior during execution",
            ]
        )
    elif risk_level == RiskLevel.MEDIUM:
        recommendations.extend(
            [
                "Review all operations before running",
                "Consider running in a controlled environment",
                "Backup affected files/configurations",
                "Monitor script execution",
            ]
        )
    else:
        recommendations.extend(
            [
                "Script appears relatively safe",
                "Review file operations to ensure expected behavior",
                "No special precautions required",
            ]
        )

    if analysis["network_ops"]:
        recommendations.append("Review all network connections for legitimacy")

    if analysis["system_ops"]:
        recommendations.append("Understand system changes before applying")

    return recommendations


def analyze_script(script_path: str) -> AnalysisResult:
    """Main analysis function"""
    path = Path(script_path)

    if not path.exists():
        raise FileNotFoundError(f"Script not found: {script_path}")

    # Read script content
    with open(path, encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # Detect language
    language = detect_language(script_path)

    # Analyze patterns
    analysis = analyze_patterns(content, language)

    # Detect high-risk patterns
    high_risk = detect_high_risk(content)
    analysis["dangerous"].extend(high_risk)

    # Extract dependencies
    dependencies = extract_dependencies(content, language)

    # Assess risk
    risk_level, risk_factors = assess_risk(analysis)

    # Generate recommendations
    recommendations = generate_recommendations(risk_level, analysis)

    # Generate purpose summary (simple heuristic)
    purpose = "Unknown purpose"
    if language == "bash":
        if "install" in content.lower():
            purpose = "Installation script"
        elif "setup" in content.lower() or "configure" in content.lower():
            purpose = "Setup/configuration script"
        elif "build" in content.lower():
            purpose = "Build script"
        elif "test" in content.lower():
            purpose = "Test script"
        elif "deploy" in content.lower():
            purpose = "Deployment script"

    # Create operations summary
    operations = []
    if analysis["file_ops"]:
        operations.append("File operations")
    if analysis["network_ops"]:
        operations.append("Network operations")
    if analysis["system_ops"]:
        operations.append("System operations")

    return AnalysisResult(
        script_path=str(path.absolute()),
        language=language,
        purpose=purpose,
        operations=operations,
        file_operations=analysis["file_ops"][:10],  # Limit output
        network_operations=analysis["network_ops"][:10],
        system_operations=analysis["system_ops"][:10],
        dependencies=dependencies,
        risk_level=risk_level.value,
        risk_factors=risk_factors,
        recommendations=recommendations,
    )


def main():
    parser = argparse.ArgumentParser(description="Analyze scripts for functionality and risks")
    parser.add_argument("script", help="Path to script file")
    parser.add_argument("--json", action="store_true", help="Output in JSON format")
    parser.add_argument("--full", action="store_true", help="Show full analysis details")

    args = parser.parse_args()

    try:
        result = analyze_script(args.script)

        if args.json:
            print(json.dumps(asdict(result), indent=2))
        else:
            print("\n" + "=" * 60)
            print("SCRIPT ANALYSIS REPORT")
            print("=" * 60)
            print(f"\n📁 Script: {result.script_path}")
            print(f"🔧 Language: {result.language}")
            print(f"🎯 Purpose: {result.purpose}")
            print(f"⚠️  Risk Level: {result.risk_level.upper()}")

            print("\n📋 Operations Detected:")
            for op in result.operations:
                print(f"  • {op}")

            limit = None if args.full else 5

            if result.file_operations:
                print(f"\n📄 File Operations ({len(result.file_operations)} found):")
                for op in result.file_operations[:limit]:
                    print(f"  • {op}")
                if limit and len(result.file_operations) > limit:
                    print(f"  ... and {len(result.file_operations) - limit} more")

            if result.network_operations:
                print(f"\n🌐 Network Operations ({len(result.network_operations)} found):")
                for op in result.network_operations[:limit]:
                    print(f"  • {op}")
                if limit and len(result.network_operations) > limit:
                    print(f"  ... and {len(result.network_operations) - limit} more")

            if result.system_operations:
                print(f"\n⚙️  System Operations ({len(result.system_operations)} found):")
                for op in result.system_operations[:limit]:
                    print(f"  • {op}")
                if limit and len(result.system_operations) > limit:
                    print(f"  ... and {len(result.system_operations) - limit} more")

            if result.dependencies:
                print("\n📦 Dependencies:")
                for dep in result.dependencies:
                    print(f"  • {dep}")

            if result.risk_factors:
                print("\n🚨 Risk Factors:")
                for factor in result.risk_factors:
                    print(f"  • {factor}")

            print("\n💡 Recommendations:")
            for rec in result.recommendations:
                print(f"  • {rec}")

            print("\n" + "=" * 60)

    except Exception as e:
        print(f"Error analyzing script: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
