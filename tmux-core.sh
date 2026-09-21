#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# tmux-core.sh - Shared tmux session management library
# Source this file, don't execute it directly
# ═══════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
TMUX_CONFIG_FILE="tmux_sessions.json"

# Directories to search in sessionizer mode (customize to your setup)
TMUX_SEARCH_DIRS=(
    ~/projects
    ~/work
    ~/.config
)

# ─────────────────────────────────────────────────────────────────────────────
# WM / Terminal Integration
#
# Override these functions to match your window manager and terminal emulator.
# Defaults: Hyprland + kitty. Set to no-ops if you don't use a tiling WM.
# ─────────────────────────────────────────────────────────────────────────────

# Move the focused window to a workspace.
# Override for your WM (i3: i3-msg workspace $1, sway: swaymsg workspace $1)
# Set to a no-op if you don't use workspaces: move_to_workspace() { :; }
move_to_workspace() {
    local workspace="$1"
    if command -v hyprctl &>/dev/null; then
        hyprctl dispatch movetoworkspace "$workspace" &>/dev/null
    fi
}

# Open a new terminal window attached to a tmux session, optionally on a workspace.
# Override for your terminal (alacritty, wezterm, foot, etc.)
open_terminal_with_session() {
    local session_name="$1"
    local workspace="$2"

    if command -v kitty &>/dev/null; then
        if [[ -n "$workspace" && "$workspace" != "null" && "$workspace" != "" ]]; then
            kitty --title "$session_name" --detach sh -c "
                command -v hyprctl &>/dev/null && hyprctl dispatch movetoworkspace $workspace
                tmux attach -t \"$session_name\"
            "
        else
            kitty --title "$session_name" --detach tmux attach -t "$session_name"
        fi
    else
        echo "Warning: No supported terminal found. Override open_terminal_with_session() in tmux-core.sh" >&2
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────────────────────────────────────

# Sanitize directory name for session naming
get_session_base_name() {
    local dir="${1:-$PWD}"
    basename "$dir" | tr ' .' '_'
}

# Get existing sessions matching base name
get_existing_sessions() {
    local base_name="$1"
    tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E "^${base_name}(_[0-9]+)?$" | sort -V
}

# Get next available session name
get_next_session_name() {
    local base_name="$1"
    local existing=$(get_existing_sessions "$base_name")

    if [[ -z "$existing" ]]; then
        echo "$base_name"
        return
    fi

    # Find the highest number
    local max=0
    while IFS= read -r session; do
        if [[ "$session" == "$base_name" ]]; then
            [[ $max -lt 1 ]] && max=1
        elif [[ "$session" =~ ^${base_name}_([0-9]+)$ ]]; then
            local num="${BASH_REMATCH[1]}"
            [[ $num -gt $max ]] && max=$num
        fi
    done <<< "$existing"

    if [[ $max -eq 0 ]]; then
        echo "$base_name"
    else
        echo "${base_name}_$((max + 1))"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Session Management
# ─────────────────────────────────────────────────────────────────────────────

# Create a new session with N windows
create_session() {
    local session_name="$1"
    local dir="$2"
    local num_windows="${3:-2}"
    local workspace="$4"

    # Create first window
    tmux new-session -d -s "$session_name" -c "$dir"

    # Create additional windows
    for ((i=2; i<=num_windows; i++)); do
        tmux new-window -t "$session_name" -c "$dir"
    done

    # Select first window
    tmux select-window -t "$session_name:0"

    # Move to workspace if specified
    if [[ -n "$workspace" ]]; then
        move_to_workspace "$workspace"
    fi
}

# Attach or switch to session
attach_or_switch() {
    local session_name="$1"

    if [[ -z "${TMUX:-}" ]]; then
        tmux attach-session -t "$session_name"
    else
        tmux switch-client -t "$session_name"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# JSON Project Config
# ─────────────────────────────────────────────────────────────────────────────

# Check if config exists
has_project_config() {
    local dir="${1:-$PWD}"
    [[ -f "$dir/$TMUX_CONFIG_FILE" ]]
}

# Get session names from config
get_project_sessions() {
    local dir="${1:-$PWD}"
    jq -r '.[].name' "$dir/$TMUX_CONFIG_FILE" 2>/dev/null
}

# Send commands to a window (handles array or string)
send_commands() {
    local session="$1"
    local window="$2"
    local window_json="$3"

    local cmd_type
    cmd_type=$(echo "$window_json" | jq -r '.command | type')

    if [[ "$cmd_type" == "array" ]]; then
        local len
        len=$(echo "$window_json" | jq -r '.command | length')
        len=$((len + 0))  # Force integer conversion

        if [[ $len -gt 0 ]]; then
            local idx=0
            while [[ $idx -lt $len ]]; do
                local cmd
                cmd=$(echo "$window_json" | jq -r ".command[$idx]")
                if [[ -n "$cmd" && "$cmd" != "null" ]]; then
                    tmux send-keys -t "$session:$window" "$cmd" C-m
                    sleep 0.1
                fi
                idx=$((idx + 1))
            done
        fi
    elif [[ "$cmd_type" == "string" ]]; then
        local cmd
        cmd=$(echo "$window_json" | jq -r '.command')
        if [[ -n "$cmd" && "$cmd" != "null" && "$cmd" != "" ]]; then
            tmux send-keys -t "$session:$window" "$cmd" C-m
        fi
    fi
}

# Resolve paths relative to a base dir, but preserve absolute and ~/ paths
resolve_tmux_path() {
    local base_dir="$1"
    local raw_path="$2"

    [[ -z "$raw_path" || "$raw_path" == "." ]] && {
        echo "$base_dir"
        return
    }

    case "$raw_path" in
        /*)
            echo "$raw_path"
            ;;
        ~/*)
            echo "${HOME}/${raw_path#~/}"
            ;;
        *)
            echo "$base_dir/$raw_path"
            ;;
    esac
}

# Spin up a single session from JSON
spin_up_session_from_json() {
    local dir="$1"
    local session_json="$2"

    local session_name=$(echo "$session_json" | jq -r '.name')
    local root_rel=$(echo "$session_json" | jq -r '.root // "."')
    local session_root
    session_root=$(resolve_tmux_path "$dir" "$root_rel")
    local workspace=$(echo "$session_json" | jq -r '.workspace // empty')

    # If session already exists, just return its name and workspace
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "$session_name:$workspace"
        return
    fi

    # Create first window
    local first_window=$(echo "$session_json" | jq '.windows[0]')
    local fw_name=$(echo "$first_window" | jq -r '.name')
    local fw_path=$(echo "$first_window" | jq -r '.path // "."')
    local fw_target
    fw_target=$(resolve_tmux_path "$session_root" "$fw_path")

    tmux new-session -d -s "$session_name" -c "$fw_target" -n "$fw_name"

    # Send commands for first window
    send_commands "$session_name" "$fw_name" "$first_window"

    # Create remaining windows
    local num_windows
    num_windows=$(echo "$session_json" | jq -r '.windows | length')
    num_windows=$((num_windows + 0))  # Force integer conversion

    local idx=1
    while [[ $idx -lt $num_windows ]]; do
        local window
        window=$(echo "$session_json" | jq ".windows[$idx]")
        local w_name
        w_name=$(echo "$window" | jq -r '.name')
        local w_path
        w_path=$(echo "$window" | jq -r '.path // "."')
        local w_target
        w_target=$(resolve_tmux_path "$session_root" "$w_path")

        tmux new-window -t "$session_name" -c "$w_target" -n "$w_name"
        send_commands "$session_name" "$w_name" "$window"
        idx=$((idx + 1))
    done

    tmux select-window -t "$session_name:0"

    # Return session name and workspace for caller to handle
    echo "$session_name:$workspace"
}

# Spin up all sessions from config
spin_up_all_sessions() {
    local dir="${1:-$PWD}"
    local config_file="$dir/$TMUX_CONFIG_FILE"

    local count=$(jq '. | length' "$config_file")
    local first_session=""

    for ((i=0; i<count; i++)); do
        local session_json=$(jq ".[$i]" "$config_file")
        local result=$(spin_up_session_from_json "$dir" "$session_json")
        local session_name="${result%%:*}"
        local workspace="${result##*:}"

        if [[ $i -eq 0 ]]; then
            first_session="$session_name"
            # Move current terminal to workspace if specified
            if [[ -n "$workspace" && "$workspace" != "null" && "$workspace" != "" ]]; then
                move_to_workspace "$workspace"
            fi
        else
            # Open subsequent sessions in new terminals
            open_terminal_with_session "$session_name" "$workspace"
        fi
    done

    echo "$first_session"
}

# ─────────────────────────────────────────────────────────────────────────────
# Template Generation
# ─────────────────────────────────────────────────────────────────────────────

generate_template() {
    local dir="${1:-$PWD}"
    local project_name=$(basename "$dir" | tr ' .' '_')
    local config_file="$dir/$TMUX_CONFIG_FILE"

    # Detect subdirectories
    local subdirs=()
    for d in "$dir"/*/; do
        [[ -d "$d" ]] || continue
        local name=$(basename "$d")
        # Skip common non-project dirs
        [[ "$name" =~ ^(node_modules|\.git|\.venv|venv|env|__pycache__|dist|build|\.next|\.cache|coverage|tmp)$ ]] && continue
        subdirs+=("$name")
    done

    # Build JSON
    local windows_dev=""
    local windows_servers=""

    if [[ ${#subdirs[@]} -gt 0 ]]; then
        for subdir in "${subdirs[@]}"; do
            [[ -n "$windows_dev" ]] && windows_dev+=","
            windows_dev+=$(cat <<EOF

      { "name": "$subdir", "path": "$subdir", "command": ["nvim"] }
EOF
)
            [[ -n "$windows_servers" ]] && windows_servers+=","
            windows_servers+=$(cat <<EOF

      { "name": "$subdir", "path": "$subdir", "command": [] }
EOF
)
        done
    else
        # No subdirs, create single window pointing to root
        windows_dev='
      { "name": "main", "path": ".", "command": ["nvim"] }'
        windows_servers='
      { "name": "main", "path": ".", "command": [] }'
    fi

    cat > "$config_file" << EOF
[
  {
    "name": "${project_name}-dev",
    "workspace": 4,
    "windows": [${windows_dev}
    ]
  },
  {
    "name": "${project_name}-servers",
    "workspace": 9,
    "windows": [${windows_servers}
    ]
  }
]
EOF

    echo "$config_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Session Utilities
# ─────────────────────────────────────────────────────────────────────────────

# Kill a named tmux session with confirmation
kill_session() {
    local session_name="$1"
    echo "Kill session '$session_name'? [y/N]: "
    read -r confirm || true
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        tmux kill-session -t "$session_name"
        echo "Session '$session_name' killed."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Menu Action Dispatch (shared by fzf and rofi menus)
# ─────────────────────────────────────────────────────────────────────────────

# Execute a selected menu action.
# Usage: execute_menu_action <selected> <dir> <num_windows> <workspace> [key_pressed]
# key_pressed is optional; "ctrl-o" opens in a new terminal instead of attaching.
execute_menu_action() {
    local selected="$1"
    local dir="$2"
    local num_windows="$3"
    local workspace="$4"
    local key_pressed="${5:-}"

    local base_name
    base_name=$(get_session_base_name "$dir")

    case "$selected" in
        "ATTACH: "*)
            local session="${selected#ATTACH: }"
            if [[ "$key_pressed" == "ctrl-o" ]]; then
                open_terminal_with_session "$session" ""
            else
                attach_or_switch "$session"
            fi
            ;;
        "NEW: "*)
            local session_name
            session_name=$(get_next_session_name "$base_name")
            create_session "$session_name" "$dir" "$num_windows" "$workspace"
            if [[ "$key_pressed" == "ctrl-o" ]]; then
                open_terminal_with_session "$session_name" "$workspace"
            else
                attach_or_switch "$session_name"
            fi
            ;;
        "PROJECT: ALL"*)
            local first
            first=$(spin_up_all_sessions "$dir")
            [[ -n "$first" ]] && attach_or_switch "$first"
            ;;
        "PROJECT: "*)
            local session_name="${selected#PROJECT: }"
            local session_json
            session_json=$(jq -r ".[] | select(.name == \"$session_name\")" "$dir/$TMUX_CONFIG_FILE")
            local result
            result=$(spin_up_session_from_json "$dir" "$session_json")
            local ws="${result##*:}"
            if [[ -n "$ws" && "$ws" != "null" && "$ws" != "" ]]; then
                move_to_workspace "$ws"
            fi
            if [[ "$key_pressed" == "ctrl-o" ]]; then
                open_terminal_with_session "$session_name" "$ws"
            else
                attach_or_switch "$session_name"
            fi
            ;;
        "GENERATE: "* | "REGENERATE: "*)
            local config_path
            config_path=$(generate_template "$dir")
            echo "Template created: $config_path"
            echo ""
            echo "Edit the file and run tm again to use it."
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Interactive Menu (fzf)
# ─────────────────────────────────────────────────────────────────────────────

build_menu_options() {
    local dir="${1:-$PWD}"
    local num_windows="${2:-2}"

    local base_name=$(get_session_base_name "$dir")
    local options=()

    # Add existing sessions
    local existing=$(get_existing_sessions "$base_name")
    if [[ -n "$existing" ]]; then
        while IFS= read -r session; do
            options+=("ATTACH: $session")
        done <<< "$existing"
    fi

    # Add new session option
    options+=("NEW: Quick session ($num_windows windows)")

    # Add project options if config exists
    if has_project_config "$dir"; then
        options+=("───────────────────────────────────")
        options+=("PROJECT: ALL (spin up everything)")
        while IFS= read -r session; do
            options+=("PROJECT: $session")
        done < <(get_project_sessions "$dir")
    fi

    # Always show generate option (can regenerate/update template)
    options+=("───────────────────────────────────")
    if has_project_config "$dir"; then
        options+=("REGENERATE: Update $TMUX_CONFIG_FILE")
    else
        options+=("GENERATE: Create $TMUX_CONFIG_FILE")
    fi

    printf '%s\n' "${options[@]}"
}

run_interactive_menu() {
    local dir="${1:-$PWD}"
    local num_windows="${2:-2}"
    local workspace="$3"

    local base_name=$(get_session_base_name "$dir")

    # Build and show menu (with Ctrl-o to open in a new terminal)
    local fzf_output
    fzf_output=$(build_menu_options "$dir" "$num_windows" | \
        fzf --prompt="tmux [$base_name] > " \
            --height=50% \
            --reverse \
            --border \
            --no-separator \
            --expect=ctrl-o)

    local fzf_lines=()
    mapfile -t fzf_lines <<< "$fzf_output"
    local key_pressed="${fzf_lines[0]:-}"
    local selected="${fzf_lines[1]:-}"

    [[ -z "$selected" ]] && return 0

    execute_menu_action "$selected" "$dir" "$num_windows" "$workspace" "$key_pressed"
}
