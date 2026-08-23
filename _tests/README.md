# 测试结构

`make test-shell` 会依次执行 `_tests/test-*.sh`（经 `bash` 运行，无需可执行位）。
`helpers.sh` 提供共享断言库（`fail`/`assert_*`），文件名不匹配 `test-*.sh`，因此
不会被当作测试执行；各测试文件自行搭建 `ROOT`/`TMP` 环境。

## 分工

| 测试文件 | 被测对象 | 覆盖要点 |
| --- | --- | --- |
| `test-bootstrap-components.sh` | `_bootstrap/{pkg-mac,pkg-linux,ssh,shell,git,tools,editors}.sh` | 组件契约、零参回退、缺少 CLT 中断、无污染静默 |
| `test-check-links.sh` | `_scripts/check-links.sh` | verify/preflight 语义、`stow_find` 类型过滤与忽略目录 |
| `test-doctor.sh` | `_scripts/doctor.sh` | 退出码契约：干净 0 / 警告 0 / 阻断非 0 |
| `test-install.sh` | `_install/install` | 组解析、去重保序、brew 带选项行合并、缺失组报错 |
| `test-net-proxy.sh` | `zsh/.zsh.d/net_proxy.sh` | on/off/set/scheme、环境变量持久化、地址校验 |
| `test-proj-setup.sh` | `proj-setup/bin/proj-setup.sh` | 模板占位符定制、vcs、rerun 不覆盖 |
| `test-skills-vendor.sh` | `_scripts/skills-vendor.sh` | 多 Vendor 发现、挂载、原生保护、同名加前缀、卸载 |
| `test-stow-sync.sh` | `_scripts/stow-sync.sh` | stow 参数传递、已有文件备份、忽略目录 |
| `test-tmux-plugins.sh` | `_scripts/tmux-plugins.sh` | TPM 克隆、set-environment、安装失败/无 server |
| `test-zsh-benchmark.sh` | `zsh/.zshrc` | 启动正确性无未捕获异常、耗时门禁（可环境变量配置） |

## 约定

- 每个测试文件头注明「被测对象 + 用法」。
- 断言统一从 `helpers.sh` 引入（`fail`/`assert_*`）；环境搭建（`ROOT`/`TMP`、清理）由各测试自行负责。
- 断言失败统一走 `fail()`，输出 `FAIL: ...` 并退出非 0。
- `assert_contains` 断言**字符串**包含，`assert_file_contains` 断言**文件**包含，勿混用。
