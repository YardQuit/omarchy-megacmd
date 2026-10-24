# guided.sh: shared steps for the MEGA widget's guided terminal dialogs.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Sourced by mega-add-sync and mega-add-backup. Needs gum and MEGAcmd.

# Prints a message and exits with status 1.
die() {
  gum style --foreground 1 "$*" >&2
  exit 1
}

# Prints an error and exits unless MEGAcmd is logged in.
require_login() {
  mega-whoami >/dev/null 2>&1 || die "MEGAcmd is not logged in. Use \"Log in to MEGA\" in the panel first."
}

# Lets the user pick a local folder below $HOME; prints its absolute path.
choose_local_folder() {
  local header=$1 picked
  picked=$(cd "$HOME" && gum file --directory --height=15 --header="$header (Enter selects, ← goes up)" "$HOME") || exit 1
  [[ -f $picked ]] && picked=$(dirname "$picked")
  [[ -d $picked ]] || die "Not a folder: $picked"
  realpath "$picked"
}

# Asks for a MEGA folder path, suggesting $1; prints the path without a trailing slash.
choose_remote_folder() {
  local header=$1 suggestion=$2 picked
  picked=$(gum input --header="$header" --value="$suggestion" --placeholder="/path/in/MEGA" --char-limit=0) || exit 1
  picked=${picked%/}
  [[ $picked == /* ]] || picked="/$picked"
  printf '%s\n' "${picked:-/}"
}

# Creates the MEGA folder $1 (and its parents) when it does not exist yet.
ensure_remote_folder() {
  local path=$1
  [[ $path == / ]] && return 0
  mega-ls "$path" >/dev/null 2>&1 && return 0
  mega-mkdir -p "$path" >/dev/null || die "Could not create $path in MEGA"
  echo "Created $path in MEGA."
}

# Lets the user pick a backup schedule; prints MEGAcmd's period string. The
# current period $1, if any, is offered first.
choose_period() {
  local current=${1:-} choice
  local options=("Daily at 02:00" "Every 6 hours" "Weekly, Sunday at 03:00" "Other…")
  [[ -n $current ]] && options=("Keep current ($current)" "${options[@]}")
  choice=$(gum choose --header="When to back up" "${options[@]}") || exit 1
  case $choice in
    "Keep current"*) printf '%s\n' "$current" ;;
    "Daily at 02:00") printf '%s\n' "0 0 2 * * *" ;;
    "Every 6 hours") printf '%s\n' "6h" ;;
    "Weekly, Sunday at 03:00") printf '%s\n' "0 0 3 * * 0" ;;
    *) gum input --header="Period: e.g. 1d, 12h, or a cron line with seconds (\"0 30 1 * * *\")" --value="$current" --char-limit=0 || exit 1 ;;
  esac
}

# Asks how many backups to keep, suggesting $1; prints a positive number.
choose_keep() {
  local keep
  keep=$(gum input --header="How many backups to keep" --value="${1:-14}" --char-limit=4) || exit 1
  [[ $keep =~ ^[1-9][0-9]*$ ]] || die "Not a number: $keep"
  printf '%s\n' "$keep"
}

# Joins a MEGA parent folder and a name.
remote_join() {
  if [[ $1 == / ]]; then printf '/%s\n' "$2"; else printf '%s/%s\n' "${1%/}" "$2"; fi
}
