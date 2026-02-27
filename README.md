# Tmux Session Manager

A tmux session management system with two entry points: `tm` (current directory) and `ts` (sessionizer/directory picker). Supports per-project JSON configs for reproducible multi-session setups.

Inspired by [ThePrimeagen's tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer).

## Requirements

- **tmux** - terminal multiplexer
- **fzf** - fuzzy finder for interactive menus
- **jq** - JSON parser for project configs

Optional (for multi-session workspace support):
- A terminal emulator that supports detached spawning (default: **kitty**)
- A tiling WM with workspace commands (default: **Hyprland**)

## Installation

```bash
git clone https://github.com/HRmemon/tmux-session-manager.git
cd tmux-session-manager

# Add to PATH (pick one)
export PATH="$PWD:$PATH"                         # temporary
ln -s "$PWD/tm" ~/.local/bin/tm                   # symlink
ln -s "$PWD/ts" ~/.local/bin/ts
```

## File Structure

```
tmux-session-manager/
├── tm              # Current directory entry point
├── ts              # Sessionizer entry point (pick dir first)
└── tmux-core.sh    # Shared library (sourced, not executed)
```

## Features

| Feature | Description |
|---------|-------------|
| Quick sessions | Create N windows in current dir with `tm -q 3` |
| Multiple sessions per dir | Auto-increments: `project`, `project_2`, `project_3` |
| Project configs | JSON file defines multi-session setups with commands |
| Workspace integration | Move terminal to WM workspace (pluggable) |
| Template generation | Auto-detect subdirs and create starter JSON |
| Attach-or-create | PROJECT options attach to existing sessions instead of recreating |

## Usage

### `tm` - Current Directory Mode

```bash
tm                 # Interactive menu (default 2 windows)
tm 3               # Menu, NEW creates 3 windows
tm -q              # Quick: skip menu, create 2 windows
tm -q 4            # Quick: create 4 windows
tm 3 -w 5          # Menu, move to workspace 5
tm -q 2 -w 9       # Quick: 2 windows on workspace 9
```

### `ts` - Sessionizer Mode

```bash
ts                    # fzf to pick dir, then interactive menu
ts ~/projects/foo     # Skip picker, go straight to menu
ts -q                 # Pick dir, quick create (no menu)
ts -q ~/projects/foo  # Quick create in specified dir
```

### Interactive Menu Options

When running `tm` or `ts`, the menu shows:

```
ATTACH: project           <- Existing sessions for this dir
ATTACH: project_2
NEW: Quick session (2 windows)
-----------------------------------
PROJECT: ALL (spin up everything)    <- If JSON config exists
PROJECT: project-dev
PROJECT: project-servers
-----------------------------------
GENERATE: Create tmux_sessions.json  <- Template generator
```

## Project Configuration

For projects you work on repeatedly, create a `tmux_sessions.json` in the project root.

### Example

```json
[
  {
    "name": "myapp-dev",
    "workspace": 4,
    "windows": [
      { "name": "editor", "path": ".", "command": ["nvim"] },
      { "name": "backend", "path": "backend", "command": [] },
      { "name": "frontend", "path": "frontend", "command": [] }
    ]
  },
  {
    "name": "myapp-servers",
    "workspace": 9,
    "windows": [
      { "name": "api", "path": "backend", "command": ["npm run dev"] },
      { "name": "web", "path": "frontend", "command": ["npm run dev"] },
      { "name": "db", "path": ".", "command": ["docker compose up db"] }
    ]
  }
]
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Session name |
| `workspace` | number | no | WM workspace to move to |
| `root` | string | no | Root path relative to JSON file (default: `.`) |
| `windows` | array | yes | List of window definitions |
| `windows[].name` | string | yes | Window name |
| `windows[].path` | string | no | Path relative to root (default: `.`) |
| `windows[].command` | string or array | no | Command(s) to run on window open |

### Command Field

The `command` field supports both formats:

```json
// Single command (string)
{ "command": "nvim" }

// Multiple commands (array) - runs sequentially
{ "command": ["source .venv/bin/activate", "python manage.py runserver"] }

// Empty (no command)
{ "command": [] }
{ "command": "" }
```

### PROJECT: ALL Behavior

When selecting "ALL":
1. First session attaches in current terminal (moves to its workspace)
2. Subsequent sessions open in new terminal windows on their respective workspaces

If a session is already running, it attaches instead of recreating.

## Customization

### Search Directories (for `ts`)

Edit `tmux-core.sh` and modify the `TMUX_SEARCH_DIRS` array:

```bash
TMUX_SEARCH_DIRS=(
    ~/projects
    ~/work
    ~/.config
)
```

### Window Manager / Terminal Integration

The workspace and terminal-spawning logic is contained in two functions at the top of `tmux-core.sh`. Override them to match your setup:

#### `move_to_workspace`

Moves the focused window to a workspace. Default: Hyprland.

```bash
# i3 / sway
move_to_workspace() {
    local workspace="$1"
    i3-msg workspace "$workspace"     # or: swaymsg workspace "$workspace"
}

# No workspace management (disable)
move_to_workspace() { :; }
```

#### `open_terminal_with_session`

Opens a new terminal attached to a tmux session. Default: kitty.

```bash
# Alacritty
open_terminal_with_session() {
    local session_name="$1"
    local workspace="$2"
    if [[ -n "$workspace" && "$workspace" != "null" && "$workspace" != "" ]]; then
        alacritty --title "$session_name" -e sh -c "
            move_to_workspace $workspace
            tmux attach -t \"$session_name\"
        " &
    else
        alacritty --title "$session_name" -e tmux attach -t "$session_name" &
    fi
}

# Wezterm
open_terminal_with_session() {
    local session_name="$1"
    wezterm start -- tmux attach -t "$session_name" &
}
```

### Template Generation

The `GENERATE` option scans for subdirectories and creates a starter JSON:
- Skips: `node_modules`, `.git`, `.venv`, `venv`, `env`, `__pycache__`, `dist`, `build`, `.next`, `.cache`, `coverage`, `tmp`
- Creates two sessions: `{project}-dev` (with nvim) and `{project}-servers` (empty commands)

## Session Naming

Sessions are named after the directory:
- Spaces and dots become underscores: `my project` -> `my_project`
- Multiple sessions: `project`, `project_2`, `project_3`, ...

## Extending

### Adding a new menu option

1. Edit `build_menu_options()` in `tmux-core.sh`
2. Add your option string to the `options` array
3. Handle it in `run_interactive_menu()` with a new `case` branch

### Adding a new flag to `tm` or `ts`

1. Add argument parsing in the `while [[ $# -gt 0 ]]` loop
2. Pass the value to `run_interactive_menu` or handle in quick mode

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Session creates infinite windows | Ensure `jq` is installed and JSON is valid: `jq . tmux_sessions.json` |
| Workspace not switching | Check your WM command. Override `move_to_workspace()` |
| Menu not showing | Check if `fzf` is installed: `which fzf` |
| Commands not running | Check command array syntax. Each element runs with Enter after it |

## License

MIT
