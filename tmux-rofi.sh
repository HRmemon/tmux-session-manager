#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# tmux-rofi.sh - Rofi frontend for tmux session management
#
# Alternative to tm/ts for users who prefer rofi over fzf.
# Usage: tmux-rofi.sh
# ═══════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/tmux-core.sh"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Rofi: Select Directory
# ─────────────────────────────────────────────────────────────────────────────
selected_dir=$(find "${TMUX_SEARCH_DIRS[@]}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | \
    sort -u | rofi -dmenu -i -p "📁 Select Project" -no-custom)

[[ -z "$selected_dir" ]] && exit 0

# ─────────────────────────────────────────────────────────────────────────────
# 2. Rofi: Select Action
# ─────────────────────────────────────────────────────────────────────────────
num_windows=2
base_name=$(get_session_base_name "$selected_dir")

selected_action=$(build_menu_options "$selected_dir" "$num_windows" | \
    rofi -dmenu -i -p "🪟 tmux [$base_name]" -no-custom)

[[ -z "$selected_action" ]] && exit 0
[[ "$selected_action" == *"────"* ]] && exit 0

# ─────────────────────────────────────────────────────────────────────────────
# 3. Execute
# ─────────────────────────────────────────────────────────────────────────────
execute_menu_action "$selected_action" "$selected_dir" "$num_windows" ""
