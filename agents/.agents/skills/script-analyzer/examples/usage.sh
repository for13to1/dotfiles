#!/bin/bash
# Example: How to use the script-analyzer skill

echo "=== Script Analyzer Usage Examples ==="
echo ""

echo "1. Analyze a script file:"
echo "   python3 ~/.agents/skills/script-analyzer/scripts/analyze.py /path/to/script.sh"
echo ""

echo "2. Get JSON output:"
echo "   python3 ~/.agents/skills/script-analyzer/scripts/analyze.py --json /path/to/script.sh"
echo ""

echo "3. Analyze with LLM (ask opencode):"
echo "   '请分析这个脚本的功能和安全性'"
echo "   'Analyze this script for functionality and safety'"
echo ""

echo "4. Example analysis of safe script:"
echo "   python3 ~/.agents/skills/script-analyzer/scripts/analyze.py ~/.agents/skills/script-analyzer/examples/safe_script.sh"
echo ""

echo "5. Example analysis of risky script:"
echo "   python3 ~/.agents/skills/script-analyzer/scripts/analyze.py ~/.agents/skills/script-analyzer/examples/risky_script.sh"
echo ""

echo "=== Best Practices ==="
echo "• Always analyze scripts before running them"
echo "• Use sandbox environment for high-risk scripts"
echo "• Backup important data before system modifications"
echo "• Monitor script execution with system tools"
