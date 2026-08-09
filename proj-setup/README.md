# proj-setup

项目初始化工具，按基础配置、版本控制和语言栈复制预设模板。

## 安装

通过 bootstrap.sh 自动部署，或手动创建符号链接：

```bash
ln -sf ~/dotfiles/proj-setup/bin/proj-setup.sh ~/.local/bin/proj-setup
```

## 用法

```bash
proj-setup [--vcs=VCS] [--lang=LANG] [目录名]
```

### 参数

- `--vcs=VCS`：指定版本控制模板目录名，默认为 `git`，可使用 `none` 跳过版本控制配置
- `--lang=LANG`：指定语言模板目录名（如 `cpp`、`python`、`rust`），可选
- `[目录名]`：目标目录，默认为当前目录

### 示例

```bash
# 当前目录，基础配置 + Git
proj-setup

# 创建新目录，基础配置 + Git
proj-setup myproject

# 当前目录，仅基础配置
proj-setup --vcs=none

# 当前目录，Git + C++ 模板
proj-setup --vcs=git --lang=cpp

# 创建新目录，Git + Python 模板
proj-setup myproject --lang=python
```

## 模板内容

### 基础配置

- `.editorconfig`：编辑器配置（缩进、编码等）

### 版本控制配置

#### Git

- `.gitignore`：Git 忽略规则
- `.gitattributes`：Git 文件属性配置（行尾、二进制标记）

### C++ 模板

- `.clang-format`：clang-format 代码格式化配置

### Python 模板

- `pyproject.toml`：项目配置、依赖、工具配置（ruff, mypy, pytest）
- `project.name` 会根据目标目录名自动生成

### Rust 模板

- `.rustfmt.toml`：rustfmt 代码格式化配置

## 行为说明

- 如果目标目录不存在，会自动创建
- 如果目标文件已存在，会跳过（不覆盖）
- 默认使用 `--vcs=git`，会复制 Git 配置并初始化 Git 仓库
- 使用 `--vcs=none` 时，只复制基础配置和语言模板，不初始化版本控制
- 如果 Git 仓库已存在，会跳过 `git init`
- 如果提供多个位置参数，会报错退出
- 使用 `--lang=python` 时，会把 `pyproject.toml` 中的项目名设置为目标目录名的规范化结果

## 添加新语言模板

1. 在 `templates/language/` 下创建新目录（如 `templates/language/go/`）
2. 添加该语言的配置文件
3. 使用 `proj-setup --lang=go` 即可应用该模板，无需修改代码

## 维护

模板文件位置：`~/dotfiles/proj-setup/templates/`

```tree
proj-setup/
├── bin/
│   └── proj-setup.sh
├── templates/
│   ├── base/
│   │   ├── .editorconfig
│   │   └── README.md
│   ├── vcs/
│   │   └── git/
│   │       ├── .gitattributes
│   │       └── .gitignore
│   └── language/
│       ├── cpp/
│       │   └── .clang-format
│       ├── python/
│       │   └── pyproject.toml
│       └── rust/
│           └── .rustfmt.toml
└── README.md
```
