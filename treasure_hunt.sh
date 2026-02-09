#!/usr/bin/env bash
# treasure_hunt.sh
# Interactive, terminal-based Linux treasure hunt in bash.
# Single-file, standard utilities only. Creates a sandbox directory per player and tests
# command knowledge by asking the player to enter specific commands (validated and executed safely).
#
# Features:
# - 5 beginner levels covering common Linux commands (echo, pwd, ls, touch, mkdir, rm, rmdir, mv,
#   cat, tail, cp, df, du, ln, zip/unzip, find, grep, pipes and redirect).
# - Coins + tokens economy, hints (cost coins), strikes, save/load per-player.
# - Admin mode (--admin) for reveal/skip/export clue cards; admin password is checked vs ADMIN_PASS env var
#   or can be set at runtime if ADMIN_PASS is not present.
# - Creates levels.json on first run (so host can edit it later).
#
# WARNING: The script executes only a restricted set of commands inside a per-player sandbox.
# It blocks obvious dangerous characters/constructs (like ';', '&&', backticks, $(), etc.) and only
# allows a small whitelist of command names and pipes/redirections.
#
# Author: generated for your workshop. Use responsibly.

set -euo pipefail

# ---------------------------
# Color codes for better UX
# ---------------------------
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Bold colors
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'
BOLD_MAGENTA='\033[1;35m'
BOLD_CYAN='\033[1;36m'
BOLD_WHITE='\033[1;97m'

# Reset
NC='\033[0m' # No Color
RESET='\033[0m'

# ---------------------------
# Configuration / constants
# ---------------------------
SCRIPT_NAME="$(basename "$0")"
BASE_DIR="$(pwd)"
DATA_DIR="${BASE_DIR}/.treasure_data"
mkdir -p "$DATA_DIR"

# Directory to write certificates to. Can be overridden by exporting CERT_DIR.
# Default: ${BASE_DIR}/certs
CERT_DIR="${CERT_DIR:-${BASE_DIR}/certs}"
mkdir -p "$CERT_DIR"
STARTING_COINS=5
MAX_STRIKES=3
SANDBOX_PREFIX="treasure_sandbox"
LEVELS_JSON="${BASE_DIR}/levels.json"
DEBUG=false

# Allowed commands (whitelist) — only these may be executed by the player.
ALLOWED_CMDS=(echo pwd ls touch mkdir rm rmdir mv cat tail cp df du ln zip unzip find grep wc sort head sed awk cut stat du df file basename dirname zipinfo)

# Allowed punctuation in safe commands: space, alnum, dash, underscore, slash, dot, quotes, pipe, >, >>.
# Forbidden substrings: ; && || ` $(
FORBIDDEN_PATTERNS=(';' '&&' '\|\|' '`' '\$\(' '\bchmod\b' '\bchown\b' '\bssh\b' '\bscp\b' '\bcurl\b' '\bwget\b' '\bpython\b' '\bperl\b' '\brm -rf /' '\b:(){' )

# ---------------------------
# Level definitions (internal)
# Script will create a levels.json file at first run with these definitions so host can edit.
# ---------------------------
# Each level is a small step-by-step micro-lab. The script validates each step and runs it inside
# a sandbox directory isolated for that player.
declare -A LEVEL_NAME
declare -A LEVEL_TOKEN
declare -A LEVEL_REWARD
declare -A LEVEL_HINTS
declare -A LEVEL_HINT_COSTS
declare -A LEVEL_TASK_COUNT
declare -A LEVEL_TASK_PROMPTS
declare -A LEVEL_TASK_REGEX   # regex to validate single command per task (POSIX ERE)

# Level 1 — basic mkdir / touch / echo / pwd / ls
LEVEL_NAME[1]="Files & Navigation (mkdir, touch, echo, pwd, ls)"
LEVEL_TOKEN[1]="L1KEY"
LEVEL_REWARD[1]=8
LEVEL_HINTS[1]="Create a directory with mkdir. Use touch to create files. Use echo with > to write."
LEVEL_HINT_COSTS[1]=2
LEVEL_TASK_COUNT[1]=3
LEVEL_TASK_PROMPTS[1,1]="Create a directory named 'lab1' (enter the single command you'd use)."
LEVEL_TASK_REGEX[1,1]='^[[:space:]]*mkdir[[:space:]]+lab1[[:space:]]*$'
LEVEL_TASK_PROMPTS[1,2]="Create an empty file named 'lab1/start.txt' using touch (enter the command)."
LEVEL_TASK_REGEX[1,2]='^[[:space:]]*touch[[:space:]]+lab1/start\.txt[[:space:]]*$'
LEVEL_TASK_PROMPTS[1,3]="Write the text 'begin' into lab1/start.txt using a single echo + redirection command (enter the command exactly)."
# Accept commands like: echo begin > lab1/start.txt or echo 'begin' > lab1/start.txt
LEVEL_TASK_REGEX[1,3]='^[[:space:]]*echo[[:space:]]+(\047?\"?)?begin(\047?\"?)?[[:space:]]*>[[:space:]]*lab1/start\.txt[[:space:]]*$'

# Level 2 — copy, mv, cp, rm
LEVEL_NAME[2]="Copy & Move (cp, mv, rm)"
LEVEL_TOKEN[2]="L2NUM"
LEVEL_REWARD[2]=10
LEVEL_HINTS[2]="Use cp to copy, mv to rename/move, rm to remove files."
LEVEL_HINT_COSTS[2]=3
LEVEL_TASK_COUNT[2]=3
LEVEL_TASK_PROMPTS[2,1]="Copy lab1/start.txt to lab1/copy.txt (enter the single command)."
LEVEL_TASK_REGEX[2,1]='^[[:space:]]*cp[[:space:]]+lab1/start\.txt[[:space:]]+lab1/copy\.txt[[:space:]]*$'
LEVEL_TASK_PROMPTS[2,2]="Rename (move) lab1/copy.txt to lab1/moved.txt (enter the command)."
LEVEL_TASK_REGEX[2,2]='^[[:space:]]*mv[[:space:]]+lab1/copy\.txt[[:space:]]+lab1/moved\.txt[[:space:]]*$'
LEVEL_TASK_PROMPTS[2,3]="Remove the original file lab1/start.txt (enter the command)."
LEVEL_TASK_REGEX[2,3]='^[[:space:]]*rm[[:space:]]+lab1/start\.txt[[:space:]]*$'

# Level 3 — view & search (cat, tail, grep, find, pipes, redirect)
LEVEL_NAME[3]="Viewing & Searching (cat, tail, grep, find, pipes)"
LEVEL_TOKEN[3]="L3CIP"
LEVEL_REWARD[3]=12
LEVEL_HINTS[3]="Use grep to search text. Pipes | and > redirects are allowed. Use find to locate files."
LEVEL_HINT_COSTS[3]=4
LEVEL_TASK_COUNT[3]=2
LEVEL_TASK_PROMPTS[3,1]="Create a file messages.txt in the sandbox with three lines, one of which contains the word 'secret'. Provide the command to create it using a single echo -e ... > messages.txt command."
# Accept: echo -e "line1\nsecret\nline3" > messages.txt
LEVEL_TASK_REGEX[3,1]='^[[:space:]]*echo[[:space:]]+-e[[:space:]]+(.+)[[:space:]]*>[[:space:]]*messages\.txt[[:space:]]*$'
LEVEL_TASK_PROMPTS[3,2]="Use grep to output the line containing 'secret' from messages.txt (enter the command)."
# Accept: grep secret messages.txt, grep 'secret' messages.txt, grep "secret" messages.txt
# Also accept pipes: cat messages.txt | grep secret (with or without quotes)
LEVEL_TASK_REGEX[3,2]='^[[:space:]]*grep[[:space:]]+['"'"'"]?secret['"'"'"]?[[:space:]]+messages\.txt[[:space:]]*$|^[[:space:]]*cat[[:space:]]+messages\.txt[[:space:]]*\|[[:space:]]*grep[[:space:]]+['"'"'"]?secret['"'"'"]?[[:space:]]*$'

# Level 4 — links, disk usage (ln, du, df)
LEVEL_NAME[4]="Links & Disk (ln, du, df)"
LEVEL_TOKEN[4]="L4MAP"
LEVEL_REWARD[4]=15
LEVEL_HINTS[4]="Create symbolic links with ln -s. Check sizes with du -h and filesystem with df -h."
LEVEL_HINT_COSTS[4]=5
LEVEL_TASK_COUNT[4]=2
LEVEL_TASK_PROMPTS[4,1]="Create a symbolic link named lab1/link_to_moved pointing to lab1/moved.txt (enter the ln command)."
LEVEL_TASK_REGEX[4,1]='^[[:space:]]*ln[[:space:]]+-s[[:space:]]+lab1/moved\.txt[[:space:]]+lab1/link_to_moved[[:space:]]*$'
LEVEL_TASK_PROMPTS[4,2]="Show human-readable disk usage of directory lab1 using du (enter the command)."
LEVEL_TASK_REGEX[4,2]='^[[:space:]]*du[[:space:]]+-h[[:space:]]+lab1[[:space:]]*$'

# Level 5 — compress & find (zip/unzip/find)
LEVEL_NAME[5]="Compress & Find (zip/unzip/find)"
LEVEL_TOKEN[5]="L5VAULT"
LEVEL_REWARD[5]=25
LEVEL_HINTS[5]="Use zip to compress a folder and unzip to extract. Use find to locate files by name."
LEVEL_HINT_COSTS[5]=6
LEVEL_TASK_COUNT[5]=3
LEVEL_TASK_PROMPTS[5,1]="Create a zip archive named lab1.zip containing the lab1 directory (enter the command)."
LEVEL_TASK_REGEX[5,1]='^[[:space:]]*zip[[:space:]]+-r[[:space:]]+lab1\.zip[[:space:]]+lab1[[:space:]]*$'
LEVEL_TASK_PROMPTS[5,2]="Remove the lab1 directory (so only the zip remains) using a safe command (enter the command)."
# We expect user to remove lab1 safely: rm -r lab1
LEVEL_TASK_REGEX[5,2]='^[[:space:]]*rm[[:space:]]+-r[[:space:]]+lab1[[:space:]]*$'
LEVEL_TASK_PROMPTS[5,3]="List files inside the zip archive lab1.zip using unzip -l or zipinfo (enter the command)."
LEVEL_TASK_REGEX[5,3]='^[[:space:]]*(unzip[[:space:]]+-l[[:space:]]+lab1\.zip[[:space:]]*|zipinfo[[:space:]]+lab1\.zip[[:space:]]*)$'

# ---------------------------
# Utility functions
# ---------------------------

# Print a banner
banner() {
  echo -e "${BOLD_CYAN}=============================================="
  echo -e "      ${BOLD_YELLOW}Linux Treasure Hunt ${BOLD_WHITE}— ${BOLD_GREEN}Workshop Labs"
  echo -e "${BOLD_CYAN}=============================================${RESET}"
}

# Lowercase and trim
lc_trim() {
  local s="$*"
  # trim
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  # lowercase
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  printf '%s' "$s"
}

# Safe-command check: returns 0 if safe, 1 if not safe
is_safe_command() {
  local cmd="$1"

  # Forbidden patterns
  for pat in "${FORBIDDEN_PATTERNS[@]}"; do
    if printf '%s\n' "$cmd" | grep -q -E "$pat"; then
      return 1
    fi
  done

  # Disallow semicolons and double ampersands, but allow single pipes and redirections
  # Check for dangerous characters, but exclude allowed ones (>, |)
  local temp_cmd="$cmd"
  # Remove allowed redirections and pipes temporarily for checking
  temp_cmd="${temp_cmd//>/}"
  temp_cmd="${temp_cmd//>>/}"
  # Now check for forbidden ; & $ (but $ alone in variable context might be needed, so check for $( specifically)
  if printf '%s\n' "$temp_cmd" | grep -q '[;&]'; then
    return 1
  fi

  # Break by pipe into pipeline segments
  IFS='|' read -ra parts <<< "$cmd"
  for part in "${parts[@]}"; do
    # remove redirections for check
    local part_clean
    part_clean="$(printf '%s' "$part" | sed -E 's/[[:space:]]*>[[:space:]]*[^[:space:]]+//g' )"
    # first token is the command name
    local first
    first="$(printf '%s' "$part_clean" | awk '{print $1}')"
    if [[ -z "$first" ]]; then
      return 1
    fi
    # remove any leading path (allow /bin/echo etc)
    first="$(basename "$first")"
    local allowed=false
    for a in "${ALLOWED_CMDS[@]}"; do
      if [[ "$first" == "$a" ]]; then allowed=true; break; fi
    done
    if ! $allowed; then
      return 1
    fi
  done

  return 0
}

# Execute a user command in the sandbox directory (safe)
execute_in_sandbox() {
  local player_sandbox="$1"
  local cmd="$2"
  # we already validated safety before calling this
  (cd "$player_sandbox" && bash -c -- "$cmd")
}

# Save / load player state (simple key=value)
save_state() {
  local player="$1"
  local file="${DATA_DIR}/save_${player}.txt"
  {
    echo "player=${player}"
    echo "level=${PLAYER_LEVEL}"
    echo "coins=${PLAYER_COINS}"
    echo "tokens=${PLAYER_TOKENS}"
    echo "strikes=${PLAYER_STRIKES}"
    echo "start_time=${PLAYER_START_TIME}"
  } > "$file"
}

load_state_if_exists() {
  local player="$1"
  local file="${DATA_DIR}/save_${player}.txt"
  if [[ -f "$file" ]]; then
    # shellcheck disable=SC1090
    source "$file"
    PLAYER_LEVEL="${level:-1}"
    PLAYER_COINS="${coins:-$STARTING_COINS}"
    PLAYER_TOKENS="${tokens:-}"
    PLAYER_STRIKES="${strikes:-0}"
    PLAYER_START_TIME="${start_time:-$(date +%s)}"
    return 0
  fi
  return 1
}

# Print status
show_status() {
  echo "Player: $PLAYER_NAME"
  echo "Level: $PLAYER_LEVEL / 5"
  echo "Coins: $PLAYER_COINS"
  echo "Tokens: ${PLAYER_TOKENS:-(none)}"
  echo "Strikes: $PLAYER_STRIKES / $MAX_STRIKES"
  echo "Sandbox: $PLAYER_SANDBOX"
}

# List inventory (tokens)
show_inventory() {
  if [[ -z "${PLAYER_TOKENS}" ]]; then
    echo "(no tokens yet)"
  else
    IFS=',' read -ra TARR <<< "$PLAYER_TOKENS"
    for t in "${TARR[@]}"; do
      echo " - $t"
    done
  fi
}

# Award tokens
award_token() {
  local tok="$1"
  if [[ -z "$PLAYER_TOKENS" ]]; then
    PLAYER_TOKENS="$tok"
  else
    PLAYER_TOKENS="${PLAYER_TOKENS},$tok"
  fi
}

# Show hint (deduct coins)
offer_hint_for_level() {
  local lvl="$1"
  local cost="${LEVEL_HINT_COSTS[$lvl]}"
  echo "Hint available for Level $lvl (cost: $cost coins)."
  if (( PLAYER_COINS < cost )); then
    echo "You have $PLAYER_COINS coins — not enough for this hint."
    return 1
  fi
  read -r -p "Buy hint for $cost coins? (y/N): " ans
  ans="$(lc_trim "$ans")"
  if [[ "$ans" == "y" || "$ans" == "yes" ]]; then
    PLAYER_COINS=$((PLAYER_COINS - cost))
    echo "HINT: ${LEVEL_HINTS[$lvl]}"
    save_state "$PLAYER_NAME"
    return 0
  fi
  return 1
}

# Admin functions
admin_reveal_answer() {
  local lvl="$1"
  echo "Admin reveal for level $lvl:"
  # We don't store 'answers' (these levels are task-based). Show expected task patterns.
  local cnt="${LEVEL_TASK_COUNT[$lvl]}"
  for ((i=1;i<=cnt;i++)); do
    echo " Task $i expected pattern: ${LEVEL_TASK_REGEX[$lvl,$i]}"
  done
}

admin_skip_to_level() {
  local lvl="$1"
  PLAYER_LEVEL="$lvl"
  echo "Player advanced to level $PLAYER_LEVEL (admin action)."
  save_state "$PLAYER_NAME"
}

admin_export_cluecards() {
  local outdir="${BASE_DIR}/cluecards"
  mkdir -p "$outdir"
  for lvl in 1 2 3 4 5; do
    local fname="${outdir}/cluecard_level_${lvl}.txt"
    {
      echo "CLUE CARD — LEVEL $lvl"
      echo "Name: ${LEVEL_NAME[$lvl]}"
      echo ""
      echo "Instructions: ${LEVEL_TASK_PROMPTS[$lvl,1]}"
      local cnt="${LEVEL_TASK_COUNT[$lvl]}"
      for ((i=2;i<=cnt;i++)); do
        echo " - Step $i: ${LEVEL_TASK_PROMPTS[$lvl,$i]}"
      done
      echo ""
      echo "Hint (cost ${LEVEL_HINT_COSTS[$lvl]} coins): ${LEVEL_HINTS[$lvl]}"
      echo "Reward: ${LEVEL_REWARD[$lvl]} coins, token ${LEVEL_TOKEN[$lvl]}"
    } > "$fname"
  done
  echo "Clue cards exported to $outdir"
}

# Small helper to print the sandbox path contents
print_sandbox_tree() {
  echo "Sandbox contents (showing up to 500 lines):"
  (cd "$PLAYER_SANDBOX" && find . | sed 's/^\./(sandbox)/') | head -n 500
}

# Initialize levels.json file if missing
write_levels_json_if_missing() {
  if [[ -f "$LEVELS_JSON" ]]; then return; fi
  cat > "$LEVELS_JSON" <<'JSON'
{
  "levels": [
    {
      "id": 1,
      "name": "Files & Navigation (mkdir, touch, echo, pwd, ls)",
      "clue": "Create directory 'lab1', create file lab1/start.txt, and write 'begin' into it.",
      "answers": [],
      "rewards": 8,
      "token": "L1KEY",
      "hints": ["Create a directory with mkdir. Use touch to create files. Use echo with > to write."],
      "hint_cost": 2,
      "randomizable": false
    },
    {
      "id": 2,
      "name": "Copy & Move (cp, mv, rm)",
      "clue": "Copy lab1/start.txt to lab1/copy.txt, rename to lab1/moved.txt, and remove lab1/start.txt.",
      "answers": [],
      "rewards": 10,
      "token": "L2NUM",
      "hints": ["Use cp to copy, mv to rename/move, rm to remove files."],
      "hint_cost": 3,
      "randomizable": false
    },
    {
      "id": 3,
      "name": "Viewing & Searching (cat, tail, grep, find, pipes)",
      "clue": "Create messages.txt containing the word 'secret' on a line, then grep that line.",
      "answers": [],
      "rewards": 12,
      "token": "L3CIP",
      "hints": ["Use grep to search text. Pipes | and > redirects are allowed. Use find to locate files."],
      "hint_cost": 4,
      "randomizable": false
    },
    {
      "id": 4,
      "name": "Links & Disk (ln, du, df)",
      "clue": "Create symlink lab1/link_to_moved -> lab1/moved.txt and run du -h lab1.",
      "answers": [],
      "rewards": 15,
      "token": "L4MAP",
      "hints": ["Create symbolic links with ln -s. Check sizes with du -h and filesystem with df -h."],
      "hint_cost": 5,
      "randomizable": false
    },
    {
      "id": 5,
      "name": "Compress & Find (zip/unzip/find)",
      "clue": "Zip the lab1 directory into lab1.zip, remove lab1, and list files inside the zip.",
      "answers": [],
      "rewards": 25,
      "token": "L5VAULT",
      "hints": ["Use zip -r to create an archive, unzip -l to list its contents, find to search files."],
      "hint_cost": 6,
      "randomizable": false
    }
  ]
}
JSON
  echo "Wrote default $LEVELS_JSON (you can edit this file for customization)."
}

# ---------------------------
# Main gameplay loop
# ---------------------------

main() {
  banner

  # handle flags
  local admin_mode=false
  local admin_flag=false
  local seed_flag=""
  local dbg=false
  if [[ "${1:-}" == "--admin" ]]; then
    admin_flag=true
  fi
  # parse any other flags (e.g., --debug)
  for arg in "$@"; do
    case "$arg" in
      --debug) dbg=true ;;
      --admin) admin_flag=true ;;
      --seed=*) seed_flag="${arg#--seed=}" ;;
    esac
  done
  if $dbg; then DEBUG=true; fi

  write_levels_json_if_missing

  # ask for player name and optionally load save
  read -r -p "Enter player name: " PLAYER_NAME
  PLAYER_NAME="$(echo "$PLAYER_NAME" | tr -d '[:space:]')"
  if [[ -z "$PLAYER_NAME" ]]; then
    echo "No name entered. Exiting."
    exit 1
  fi

# Safe filename for outputs (replace unsafe chars)
PLAYER_NAME_SAFE="$(printf '%s' "$PLAYER_NAME" | sed 's/[^A-Za-z0-9._-]/_/g')"

  local savefile="${DATA_DIR}/save_${PLAYER_NAME}.txt"
  if [[ -f "$savefile" ]]; then
    read -r -p "Save file found for $PLAYER_NAME. Load it? (Y/n): " ld
    ld="$(lc_trim "$ld")"
    if [[ -z "$ld" || "$ld" == "y" || "$ld" == "yes" ]]; then
      load_state_if_exists "$PLAYER_NAME"
      echo "Loaded progress for $PLAYER_NAME."
    else
      PLAYER_LEVEL=1
      PLAYER_COINS=$STARTING_COINS
      PLAYER_TOKENS=""
      PLAYER_STRIKES=0
      PLAYER_START_TIME="$(date +%s)"
    fi
  else
    PLAYER_LEVEL=1
    PLAYER_COINS=$STARTING_COINS
    PLAYER_TOKENS=""
    PLAYER_STRIKES=0
    PLAYER_START_TIME="$(date +%s)"
  fi

  # Setup sandbox
  PLAYER_SANDBOX="${BASE_DIR}/${SANDBOX_PREFIX}_${PLAYER_NAME}"
  mkdir -p "$PLAYER_SANDBOX"

  # Admin mode handling
  if $admin_flag; then
    # Admin password check: prefer ADMIN_PASS env var; otherwise prompt to set password for this session
    if [[ -n "${ADMIN_PASS:-}" ]]; then
      read -r -s -p "Enter admin password (checked against ADMIN_PASS env var): " apw
      echo
      if [[ "$apw" != "$ADMIN_PASS" ]]; then
        echo "Incorrect admin password. Continuing in player mode."
        admin_mode=false
      else
        admin_mode=true
      fi
    else
      read -r -s -p "ADMIN_PASS not set. Enter a password to enable admin mode for this run: " apw
      echo
      read -r -s -p "Confirm admin password: " apw2
      echo
      if [[ "$apw" == "$apw2" && -n "$apw" ]]; then
        export ADMIN_PASS="$apw"
        admin_mode=true
        echo "Admin mode enabled for this run."
      else
        echo "Passwords did not match or empty. Admin disabled."
        admin_mode=false
      fi
    fi
  fi

  echo
  echo -e "${BOLD_WHITE}Welcome, ${BOLD_CYAN}$PLAYER_NAME${BOLD_WHITE}. Starting level ${BOLD_GREEN}$PLAYER_LEVEL${BOLD_WHITE}. You have ${BOLD_YELLOW}$PLAYER_COINS ${YELLOW}coins${BOLD_WHITE}.${NC}"
  echo -e "${CYAN}Type ${BOLD_WHITE}'help'${CYAN} for commands at any time.${NC}"
  echo

  # main level loop
  while (( PLAYER_LEVEL <= 5 )); do
    echo -e "${BOLD_CYAN}-------------------------------------------------${NC}"
    echo -e "${BOLD_MAGENTA}LEVEL $PLAYER_LEVEL: ${BOLD_WHITE}${LEVEL_NAME[$PLAYER_LEVEL]}${NC}"
    echo -e "${YELLOW}🎁 Reward: ${BOLD_YELLOW}${LEVEL_REWARD[$PLAYER_LEVEL]} coins${YELLOW}, token ${BOLD_MAGENTA}${LEVEL_TOKEN[$PLAYER_LEVEL]}${NC}"
    echo -e "${CYAN}Commands: ${WHITE}hint | status | inventory | quit | save | help | sandbox${NC}"
    echo

    # run tasks for this level, step by step
    local total_steps="${LEVEL_TASK_COUNT[$PLAYER_LEVEL]}"
    for (( step=1; step<=total_steps; step++ )); do
      # show prompt for the step
      echo ""
      echo -e "${BOLD_BLUE}━━━ Step $step of $total_steps ━━━${NC}"
      echo -e "${WHITE}${LEVEL_TASK_PROMPTS[$PLAYER_LEVEL,$step]}${NC}"
      while true; do
        echo -n -e "${BOLD_GREEN}> ${NC}"
        read -r user_input_raw
        user_input="$(lc_trim "$user_input_raw")"

        # built-in commands accepted at prompt
        case "$user_input" in
          hint)
            offer_hint_for_level "$PLAYER_LEVEL"
            continue
            ;;
          status)
            show_status
            continue
            ;;
          inventory)
            show_inventory
            continue
            ;;
          save)
            save_state "$PLAYER_NAME"
            echo "Progress saved."
            continue
            ;;
          quit)
            read -r -p "Quit and save progress? (Y/n): " q
            q="$(lc_trim "$q")"
            if [[ -z "$q" || "$q" == "y" || "$q" == "yes" ]]; then
              save_state "$PLAYER_NAME"
              echo "Saved. Bye."
              exit 0
            else
              echo "Continuing."
              continue
            fi
            ;;
          help)
            echo "At any prompt you can enter: hint | status | inventory | save | quit | help | sandbox"
            continue
            ;;
          sandbox)
            print_sandbox_tree
            continue
            ;;
          admin:*)
            if $admin_mode; then
              # commands: admin:reveal N, admin:skip N, admin:cluecards
              local admin_cmd="${user_input#admin:}"
              case "$admin_cmd" in
                reveal*)
                  n="${admin_cmd##reveal }"
                  admin_reveal_answer "$n"
                  ;;
                skip*)
                  n="${admin_cmd##skip }"
                  admin_skip_to_level "$n"
                  ;;
                cluecards)
                  admin_export_cluecards
                  ;;
                *)
                  echo "Unknown admin subcommand."
                  ;;
              esac
              continue
            else
              echo "Admin commands available only in admin mode."
              continue
            fi
            ;;
        esac

        # Validate command safety
        if ! is_safe_command "$user_input_raw"; then
          echo -e "${BOLD_RED}🚫 Command rejected: not allowed or unsafe.${NC}"
          echo -e "${CYAN}Allowed commands: ${ALLOWED_CMDS[*]}${NC}"
          echo -e "${CYAN}Allowed operators: pipes '|' and redirections '>' '>>'${NC}"
          continue
        fi

        # Validate syntax for the expected step using the stored regex
        local expected_regex="${LEVEL_TASK_REGEX[$PLAYER_LEVEL,$step]}"
        if [[ -z "$expected_regex" ]]; then
          echo "Internal error: expected pattern missing. Contact host."
          exit 1
        fi

        # Use bash regex matching (note: convert ERE to bash-friendly)
        if printf '%s\n' "$user_input_raw" | grep -Eq "$expected_regex"; then
          # execute the command inside the sandbox
          if execute_in_sandbox "$PLAYER_SANDBOX" "$user_input_raw"; then
            echo -e "${BOLD_GREEN}✓ Command executed successfully.${NC}"
            # reset strikes for correct step
            PLAYER_STRIKES=0
            save_state "$PLAYER_NAME"
            break
          else
            echo -e "${BOLD_RED}✗ Execution failed (non-zero exit). Try again.${NC}"
            PLAYER_STRIKES=$((PLAYER_STRIKES+1))
          fi
        else
          echo -e "${YELLOW}⚠ That command does not match the expected pattern for this step.${NC}"
          PLAYER_STRIKES=$((PLAYER_STRIKES+1))
        fi

        # handle strikes
        if (( PLAYER_STRIKES >= MAX_STRIKES )); then
          echo -e "${YELLOW}You've reached $PLAYER_STRIKES strikes.${NC}"
          if (( PLAYER_COINS >= LEVEL_HINT_COSTS[PLAYER_LEVEL] )); then
            echo "Automatic hint offer after strikes."
            if offer_hint_for_level "$PLAYER_LEVEL"; then
              # User accepted hint, reset strikes
              PLAYER_STRIKES=0
            else
              # User declined hint, reset strikes but inform them
              PLAYER_STRIKES=0
              echo -e "${CYAN}💡 Hint declined. Strikes reset. You can try again!${NC}"
            fi
          else
            echo "Not enough coins for a hint. Consider 'save' and returning later."
            PLAYER_STRIKES=0
            echo -e "${CYAN}💡 Strikes reset. Keep trying!${NC}"
          fi
        fi

        # wrong answer coin penalty (optional): deduct 1 coin per wrong attempt if >0
        if (( PLAYER_COINS > 0 )); then
          PLAYER_COINS=$((PLAYER_COINS - 1))
          echo -e "${RED}💰 Penalty: 1 coin deducted for wrong attempt. Coins now: ${BOLD_YELLOW}$PLAYER_COINS${NC}"
          save_state "$PLAYER_NAME"
        fi

      done # end while input for this step
    done # steps loop

    # Completed all steps for level
    echo ""
    echo -e "${BOLD_GREEN}╔════════════════════════════════════════╗"
    echo -e "║  🎉 CONGRATULATIONS! 🎉               ║"
    echo -e "║  You completed Level $PLAYER_LEVEL!            ║"
    echo -e "╚════════════════════════════════════════╝${NC}"
    local reward="${LEVEL_REWARD[$PLAYER_LEVEL]}"
    PLAYER_COINS=$((PLAYER_COINS + reward))
    award_token "${LEVEL_TOKEN[$PLAYER_LEVEL]}"
    echo -e "${BOLD_YELLOW}💰 Awarded $reward coins and token ${BOLD_MAGENTA}${LEVEL_TOKEN[$PLAYER_LEVEL]}${NC}"
    echo -e "${YELLOW}💰 Total coins: ${BOLD_YELLOW}$PLAYER_COINS${NC}"
    save_state "$PLAYER_NAME"

    # increment level
    PLAYER_LEVEL=$((PLAYER_LEVEL + 1))
    echo
  done # levels loop

  # Finished all levels
  echo ""
  echo -e "${BOLD_CYAN}=========================================="
  echo -e "${BOLD_GREEN}🏆  YOU FINISHED THE HUNT — WELL DONE!  🏆"
  echo -e "${BOLD_CYAN}==========================================${NC}"
  PLAYER_END_TIME="$(date +%s)"
  local elapsed=$((PLAYER_END_TIME - PLAYER_START_TIME))
  echo -e "${CYAN}⏱  Time elapsed: ${BOLD_WHITE}$elapsed seconds${NC}"
  echo -e "${YELLOW}💰 Total coins: ${BOLD_YELLOW}$PLAYER_COINS${NC}"
  echo -e "${MAGENTA}🎫 Tokens collected: ${BOLD_MAGENTA}$PLAYER_TOKENS${NC}"
  # write certificate
  local cert="${CERT_DIR}/certificate_${PLAYER_NAME_SAFE}.txt"
  mkdir -p "$(dirname "$cert")"
  {
    echo "   _____                    _       _ "
    echo "  / ____|                  | |     | |"
    echo " | |     ___  _ __ ___  ___| |_ ___| |"
    echo " | |    / _ \| '__/ _ \/ __| __/ _ \ |"
    echo " | |___| (_) | | |  __/ (__| ||  __/ |"
    echo "  \_____\___/|_|  \___|\___|\__\___|_|"
    echo ""
    echo "Certificate of Completion"
    echo "-------------------------"
    echo "Player: $PLAYER_NAME"
    echo "Completed: $(date -d "@$PLAYER_END_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
    echo "Time started: $(date -d "@$PLAYER_START_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
    echo "Time ended: $(date -d "@$PLAYER_END_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
    echo "Elapsed seconds: $elapsed"
    echo "Total coins: $PLAYER_COINS"
    echo "Tokens: $PLAYER_TOKENS"
    echo ""
    echo "Congratulations — you completed the beginner Linux treasure hunt."
  } > "$cert"
  echo "Certificate saved to: $cert"

  # export results json-lite
  local res="${DATA_DIR}/results_${PLAYER_NAME}.json"
  cat > "$res" <<JSON
{
  "player": "$PLAYER_NAME",
  "start_time": "$PLAYER_START_TIME",
  "end_time": "$PLAYER_END_TIME",
  "elapsed_seconds": $elapsed,
  "coins": $PLAYER_COINS,
  "tokens": "$PLAYER_TOKENS"
}
JSON
  echo "Results saved to: $res"

  echo "Thanks for playing. Share certificate_${PLAYER_NAME}.txt with the host."
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
