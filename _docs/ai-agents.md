# AI Agents

内置 skills 位于 `agents/.agents/skills/`，外部 Vendor skills 位于 `_vendor/`，统一挂载到
`~/.agents/skills/`。

```bash
make skills-list
make skills-attach VENDOR=mattpocock
make skills-detach VENDOR=mattpocock
make skills-update VENDOR=mattpocock
```
