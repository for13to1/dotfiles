# shellcheck shell=bash
# tmux-resurrect 恢复前钩子（source 使用，不直接执行）。
#
# continuum 后台保存撞上 server 退出会写出空档或只有 session 头的半截档；resurrect 只判文件
# 存在，于是恢复出 0 个 pane、再被 handle_session_0 杀掉 session 0（prefix+C-r 直接退 tmux）。
# 必须 source 进 restore.sh 进程：插件函数在此可见，RESTORED_SESSION_0 也只在同进程内写回有效。
#
# 坏档 = 无 pane 行：回指最新完整档（文件名即时间序）并清掉坏档；没有完整档时保留 last 并
# 抑制 session-0 kill —— 删 last 只会让 restore 读悬空路径刷错。

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
