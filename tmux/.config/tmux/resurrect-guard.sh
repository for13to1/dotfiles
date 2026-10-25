# shellcheck shell=bash
# tmux-resurrect 恢复前钩子（source 使用，不直接执行）。
#
# continuum 后台保存撞上 server 退出会写出空档或只有 session 头的半截档；resurrect 只判文件
# 存在，于是恢复出 0 个 pane、再被 handle_session_0 杀掉 session 0（prefix+C-r 直接退 tmux）。
# 必须 source 进 restore.sh 进程：插件函数在此可见，RESTORED_SESSION_0 也只在同进程内写回有效。
#
# 坏档：没有 pane 行的存档。发现坏档时，把 last 回指到最新的完整档（文件名即时间序），
# 并删掉坏档。一个完整档都没有时，抑制 session-0 kill，last 保持原样 —— 删掉它只会让
# restore 报 "not found" 并跳过整次恢复。
#
# 竞态：本钩子扫完、restore 读 last 之前，continuum 的后台 save 仍可能写入新的坏档并重指
# last。此时钩子已返回 0，kill 未被抑制，session 0 会被杀掉；只有返回 1（无完整档可回指）
# 的路径能保住会话。要彻底闭合，需要 resurrect 侧加锁。

_resurrect_pane_ok() { [ -s "$1" ] && grep -q "^pane" "$1"; }

_resurrect_guard() {
	# rg_ 前缀：本函数跑在 restore.sh 进程内，短名会遮蔽其同名变量、让插件函数读到空值
	local rg_last rg_dir rg_best="" rg_file
	rg_last="$(last_resurrect_file)"
	rg_dir="$(resurrect_dir)"
	if _resurrect_pane_ok "$rg_last"; then
		return 0
	fi
	for rg_file in "$rg_dir"/tmux_resurrect_*.txt; do
		_resurrect_pane_ok "$rg_file" || continue
		# 文件名即时间序，取字典序最大；比 mtime 确定（同 mtime 也不会选到旧档）
		if [[ -z "$rg_best" || "$rg_file" > "$rg_best" ]]; then
			rg_best="$rg_file"
		fi
	done
	if [[ -z "$rg_best" ]]; then
		return 1
	fi
	ln -sfn "$(basename "$rg_best")" "$rg_last"
	for rg_file in "$rg_dir"/tmux_resurrect_*.txt; do
		_resurrect_pane_ok "$rg_file" || rm -f "$rg_file"
	done
}

_resurrect_guard || { declare -F restored_session_0_true >/dev/null && restored_session_0_true; }
