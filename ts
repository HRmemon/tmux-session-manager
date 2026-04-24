#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# ts — tmux sessionizer (pick directory first, then manage session)
#
# Usage:
#   ts                    fzf to pick dir, then interactive menu
#   ts ~/projects/foo     Skip dir picker, menu for that dir
#   ts -q                 fzf to pick dir, quick create (no menu)
#   ts -q ~/projects/foo  Quick create in specified dir
# ═══════════════════════════════════════════════════════════════════════════
exec "$(dirname "$(readlink -f "$0")")/tmux-manager" "$@"
