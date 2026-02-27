#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# tm - tmux session manager for current directory
#
# Usage:
#   tm                 # Interactive menu (default 2 windows)
#   tm 3               # Interactive menu, NEW creates 3 windows
#   tm -q              # Quick: create 2 windows, skip menu
#   tm -q 3            # Quick: create 3 windows, skip menu
#   tm 3 -w 5          # Interactive, workspace 5
#   tm -q 3 -w 5       # Quick: 3 windows on workspace 5
# ═══════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$SCRIPT_DIR/tmux-core.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Parse Arguments
# ─────────────────────────────────────────────────────────────────────────────
quick_mode=false
num_windows=2
workspace=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--quick)
            quick_mode=true
            shift
            ;;
        -w|--workspace)
            workspace="$2"
            shift 2
            ;;
        [0-9]*)
            num_windows="$1"
            shift
            ;;
        -h|--help)
            echo "tm - tmux session manager for current directory"
            echo ""
            echo "Usage:"
            echo "  tm                 Interactive menu (default 2 windows)"
            echo "  tm 3               Interactive menu, NEW creates 3 windows"
            echo "  tm -q              Quick: create 2 windows, skip menu"
            echo "  tm -q 3            Quick: create 3 windows, skip menu"
            echo "  tm 3 -w 5          Interactive, move to workspace 5"
            echo "  tm -q 3 -w 5       Quick: 3 windows on workspace 5"
            echo ""
            echo "Options:"
            echo "  -q, --quick        Skip menu, create session immediately"
            echo "  -w, --workspace N  Move to Hyprland workspace N"
            echo "  -h, --help         Show this help"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
if $quick_mode; then
    base_name=$(get_session_base_name "$PWD")
    session_name=$(get_next_session_name "$base_name")
    create_session "$session_name" "$PWD" "$num_windows" "$workspace"
    attach_or_switch "$session_name"
else
    run_interactive_menu "$PWD" "$num_windows" "$workspace"
fi
