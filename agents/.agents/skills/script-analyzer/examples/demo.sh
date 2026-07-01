#!/bin/bash
# 示例：如何使用 script-analyzer skill 分析脚本

echo "=== Script Analyzer Skill 使用演示 ==="
echo ""

# 检查是否提供了脚本参数
if [ $# -eq 0 ]; then
    echo "使用方法: $0 <脚本路径>"
    echo ""
    echo "示例:"
    echo "  $0 examples/safe_script.sh"
    echo "  $0 examples/risky_script.sh"
    echo "  $0 examples/python_example.py"
    exit 1
fi

SCRIPT_PATH="$1"

# 检查文件是否存在
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "错误: 文件不存在 - $SCRIPT_PATH"
    exit 1
fi

echo "📁 分析脚本: $SCRIPT_PATH"
echo ""

# 运行分析
python3 ~/.agents/skills/script-analyzer/scripts/analyze.py "$SCRIPT_PATH"

echo ""
echo "=== 分析完成 ==="
echo ""
echo "提示:"
echo "  • 使用 --json 参数获取 JSON 格式输出"
echo "  • 高风险脚本建议在沙箱环境中运行"
echo "  • 运行前请备份重要数据"
