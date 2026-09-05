# AI Agents 与技能架构

`agents` 模块提供 AI Agent 的通用规范与技能基础设施，由 Stow 挂载至 `~/.agents/`。

## 目录结构

```text
dotfiles/
├── agents/.agents/
│   ├── AGENTS.md               # 通用原则（八荣八耻与 Karpathy 准则）
│   └── skills/                 # 随仓技能（Bundled Skills）
│       ├── commit-summarizer/  # 暂存区分析与 Conventional Commits 生成
│       ├── pdf2md-polish/      # Markdown 格式修复与清洗
│       └── script-analyzer/    # 脚本静态风险扫描
├── _vendor/                    # 外部技能 Submodule 仓库
└── _scripts/skills-vendor.sh   # 外部技能插拔管理脚本
```

## 随仓技能 (Bundled Skills)

随仓技能为随本仓库直接分发并版本管理的实体目录，采用静态脚本结构化提取与 LLM 语义判断结合的方式运行：

- **`commit-summarizer`**：通过 `analyze_staged.py` 解析暂存区文件变更、重构信号与模块分布，输出结构化 JSON 并生成提交信息。
- **`pdf2md-polish`**：通过 `polish.py` 修复 PDF 提取 Markdown 的断行、标题层级与中英空格混排。
- **`script-analyzer`**：通过 `analyze.py` 静态扫描目标脚本中的高危模式（命令提权、危险删除、网络请求等）并输出风险分级。

### 新增随仓技能规范

- 技能目录位于 `agents/.agents/skills/<skill-name>/`。
- 新增技能需同步在 [`agents/.agents/skills/.gitignore`](../agents/.agents/skills/.gitignore) 中添加取反白名单规则（如 `!/<skill-name>/`），以解除顶级 `/*` 对外部 Vendor 软链接的通用忽略阻断。

## 外部技能管理 (Vendor)

由 [`_scripts/skills-vendor.sh`](../_scripts/skills-vendor.sh) 负责 `_vendor/` 下子模块技能的挂载与卸载：

```bash
make skills-list                       # 列出随仓技能、当前已挂载外部技能与可用 Vendor
make skills-attach [VENDOR=<name>]     # 初始化 Submodule 并建立技能软链接
make skills-detach [VENDOR=<name>]     # 移除外部技能软链接
make skills-update [VENDOR=<name>]     # 更新 Submodule 至上游最新提交并重新挂载
```

### 命名与覆盖规则

- **随仓技能保护**：外部技能与随仓技能同名时，跳过外部技能，不覆盖随仓目录。
- **跨 Vendor 冲突消解**：多 Vendor 包含同名技能时，后载入的技能自动增加 `<vendor>-` 前缀（如 `mattpocock-skillname`）。
