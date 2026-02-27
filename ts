#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# ts - tmux sessionizer (pick directory first, then manage session)
#
# Usage:
#   ts                    # fzf to pick dir, then interactive menu
#   ts ~/projects/foo       # Skip dir picker, go to menu for that dir
#   ts -q                 # fzf to pick dir, quick create (no menu)
#   ts -q ~/projects/foo    # Quick create session in specified dir
# ═══════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/tmux-core.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Parse Arguments
# ─────────────────────────────────────────────────────────────────────────────
quick_mode=false
selected=""
num_windows=2

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--quick)
            quick_mode=true
            shift
            ;;
        -h|--help)
            echo "ts - tmux sessionizer"
            echo ""
            echo "Usage:"
            echo "  ts                    fzf to pick dir, then interactive menu"
            echo "  ts ~/projects/foo       Skip dir picker, menu for that dir"
            echo "  ts -q                 fzf to pick dir, quick create"
            echo "  ts -q ~/projects/foo    Quick create in specified dir"
            echo ""
            echo "Options:"
            echo "  -q, --quick           Skip menu, create session immediately"
            echo "  -h, --help            Show this help"
            echo ""
            echo "Search directories:"
            for d in "${TMUX_SEARCH_DIRS[@]}"; do
                echo "  - $d"
            done
            exit 0
            ;;
        *)
            # Assume it's a directory path
            if [[ -d "$1" ]]; then
                selected="$1"
            fi
            shift
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Directory Selection
# ─────────────────────────────────────────────────────────────────────────────
if [[ -z "$selected" ]]; then
    # Build list of directories from search paths
    selected=$(find "${TMUX_SEARCH_DIRS[@]}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | \
        sort -u | \
        fzf --prompt="Select project > " \
            --height=50% \
            --reverse \
            --border \
            --preview='ls -la {} 2>/dev/null | head -20' \
            --preview-window=right:40%)
fi

[[ -z "$selected" ]] && exit 0

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
if $quick_mode; then
    base_name=$(get_session_base_name "$selected")
    session_name=$(get_next_session_name "$base_name")
    create_session "$session_name" "$selected" "$num_windows" ""
    attach_or_switch "$session_name"
else
    run_interactive_menu "$selected" "$num_windows" ""
fi
