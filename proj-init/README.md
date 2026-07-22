# proj-init

项目初始化工具，快速复制预设配置模板并初始化 git 仓库。

## 安装

通过 bootstrap.sh 自动部署，或手动创建符号链接：

```bash
ln -sf ~/dotfiles/proj-init/bin/proj-init.sh ~/.local/bin/proj-init
```

## 用法

```bash
proj-init [--lang=LANG] [目录名]
```

### 参数

- `--lang=LANG`：指定语言模板目录名（如 `cpp`、`python`、`rust`），可选
- `[目录名]`：目标目录，默认为当前目录

### 示例

```bash
# 当前目录，仅 common 模板
proj-init

# 创建新目录，仅 common 模板
proj-init myproject

# 当前目录，C++ 模板
proj-init --lang=cpp

# 创建新目录，Python 模板
proj-init myproject --lang=python
```

## 模板内容

### Common 模板（所有项目）

- `.gitignore`：通用 git 忽略规则
- `.gitattributes`：文件属性配置（行尾、二进制标记）
- `.editorconfig`：编辑器配置（缩进、编码等）

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
- 如果 git 仓库已存在，会跳过 git init
- 如果提供多个位置参数，会报错退出
- 使用 `--lang=python` 时，会把 `pyproject.toml` 中的项目名设置为目标目录名的规范化结果

## 添加新语言模板

1. 在 `templates/` 下创建新目录（如 `templates/go/`）
2. 添加该语言的配置文件
3. 使用 `proj-init --lang=go` 即可应用该模板，无需修改代码

## 维护

模板文件位置：`~/dotfiles/proj-init/templates/`

```
proj-init/
├── bin/
│   └── proj-init.sh
├── templates/
│   ├── common/
│   │   ├── .editorconfig
│   │   ├── .gitattributes
│   │   └── .gitignore
│   ├── cpp/
│   │   └── .clang-format
│   ├── python/
│   │   └── pyproject.toml
│   └── rust/
│       └── .rustfmt.toml
└── README.md
```
