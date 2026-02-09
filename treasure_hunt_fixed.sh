#!/usr/bin/env bash
# treasure_hunt.sh - FIXED VERSION
# Interactive, terminal-based Linux treasure hunt in bash.
# Fixed regex patterns and improved command validation

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

STARTING_COINS=5
MAX_STRIKES=3
SANDBOX_PREFIX="treasure_sandbox"
LEVELS_JSON="${BASE_DIR}/levels.json"
DEBUG=false

# Allowed commands (whitelist) — only these may be executed by the player.
ALLOWED_CMDS=(echo pwd ls touch mkdir rm rmdir mv cat tail cp df du ln zip unzip find grep wc sort head sed awk cut stat file basename dirname zipinfo tree)

# Allowed punctuation in safe commands: space, alnum, dash, underscore, slash, dot, quotes, pipe, >, >>.
# Forbidden substrings: ; && || ` $(
FORBIDDEN_PATTERNS=(';' '&&' '\|\|' '`' '\$\(' '\bchmod\b' '\bchown\b' '\bssh\b' '\bscp\b' '\bcurl\b' '\bwget\b' '\bpython\b' '\bperl\b' '\brm -rf /' '\b:(){' )

# ---------------------------
# Level definitions (internal)
# ---------------------------
declare -A LEVEL_NAME
declare -A LEVEL_TOKEN
declare -A LEVEL_REWARD
declare -A LEVEL_HINTS
declare -A LEVEL_HINT_COSTS
declare -A LEVEL_TASK_COUNT
declare -A LEVEL_TASK_PROMPTS
declare -A LEVEL_TASK_REGEX

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
# FIXED: More flexible pattern to accept different zip command variations
LEVEL_TASK_REGEX[5,1]='^[[:space:]]*zip[[:space:]]+-r[[:space:]]+lab1\.zip[[:space:]]+lab1/?[[:space:]]*$'

LEVEL_TASK_PROMPTS[5,2]="Remove the lab1 directory (so only the zip remains) using a safe command (enter the command)."
# FIXED: Corrected the regex syntax error - was [[:space:]]?+ which is invalid
LEVEL_TASK_REGEX[5,2]='^[[:space:]]*rm[[:space:]]+-r[[:space:]]*-?f?[[:space:]]*lab1/?[[:space:]]*$'

LEVEL_TASK_PROMPTS[5,3]="List files inside the zip archive lab1.zip using unzip -l or zipinfo (enter the command)."
LEVEL_TASK_REGEX[5,3]='^[[:space:]]*(unzip[[:space:]]+-l[[:space:]]+lab1\.zip[[:space:]]*|zipinfo[[:space:]]+lab1\.zip[[:space:]]*)$'

# ---------------------------
# Global vars per player session
# ---------------------------
PLAYER_NAME=""
PLAYER_SANDBOX=""
PLAYER_LEVEL=1
PLAYER_COINS=$STARTING_COINS
PLAYER_TOKENS=""
PLAYER_START_TIME=""
PLAYER_END_TIME=""
PLAYER_STRIKES=0

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
  local temp_cmd="$cmd"
  temp_cmd="${temp_cmd//>/}"
  temp_cmd="${temp_cmd//>>/}"
  temp_cmd="${temp_cmd//|/}"
  # Check for backticks, $(), etc.
  if [[ "$temp_cmd" =~ [';''\$''\`'] ]]; then
    return 1
  fi

  # Check allowed commands: extract the first "word" from cmd (split on spaces/pipes/redirects)
  local first_word
  first_word="$(printf '%s\n' "$cmd" | awk '{print $1}')"

  local allowed=false
  for allowed_cmd in "${ALLOWED_CMDS[@]}"; do
    if [[ "$first_word" == "$allowed_cmd" ]]; then
      allowed=true
      break
    fi
  done

  if ! $allowed; then
    return 1
  fi

  return 0
}

# Execute command safely inside player's sandbox
execute_in_sandbox() {
  local sandbox_dir="$1"
  local cmd="$2"

  if [[ ! -d "$sandbox_dir" ]]; then
    echo "Sandbox not found. Contact host."
    return 1
  fi

  # Change to sandbox directory and execute the command
  if (cd "$sandbox_dir" && eval "$cmd"); then
    return 0
  else
    return 1
  fi
}

# Show file tree for sandbox (limited)
print_sandbox_tree() {
  echo -e "${CYAN}📁 Your sandbox contents:${NC}"
  if command -v tree &> /dev/null; then
    tree -L 3 "$PLAYER_SANDBOX" || ls -lR "$PLAYER_SANDBOX"
  else
    # Fallback if tree not available
    (cd "$PLAYER_SANDBOX" && find . -maxdepth 3 -print | sed 's|^\./||' | sort) || echo "Cannot display sandbox."
  fi
}

# Show player status
show_status() {
  echo -e "${BOLD_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e " ${BOLD_WHITE}Player: ${BOLD_YELLOW}$PLAYER_NAME"
  echo -e " ${BOLD_WHITE}Level: ${BOLD_GREEN}$PLAYER_LEVEL / 5"
  echo -e " ${BOLD_WHITE}Coins: ${BOLD_YELLOW}💰 $PLAYER_COINS"
  echo -e " ${BOLD_WHITE}Tokens: ${BOLD_MAGENTA}$PLAYER_TOKENS"
  echo -e " ${BOLD_WHITE}Strikes: ${BOLD_RED}$PLAYER_STRIKES / $MAX_STRIKES"
  echo -e "${BOLD_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Show inventory
show_inventory() {
  echo -e "${BOLD_MAGENTA}🎫 Tokens collected: ${NC}${PLAYER_TOKENS:-none}"
  echo -e "${BOLD_YELLOW}💰 Coins: ${NC}${PLAYER_COINS}"
}

# Award a token to the player
award_token() {
  local token="$1"
  if [[ -z "$PLAYER_TOKENS" ]]; then
    PLAYER_TOKENS="$token"
  else
    PLAYER_TOKENS="${PLAYER_TOKENS}, ${token}"
  fi
}

# Offer hint for level (return 0 if hint given, 1 if declined)
offer_hint_for_level() {
  local lvl="$1"
  local cost="${LEVEL_HINT_COSTS[$lvl]}"
  local hint_text="${LEVEL_HINTS[$lvl]}"

  if (( PLAYER_COINS < cost )); then
    echo -e "${RED}Not enough coins for a hint. You need $cost coins but have $PLAYER_COINS.${NC}"
    return 1
  fi

  echo -e "${YELLOW}💡 Hint available for $cost coins. Current coins: $PLAYER_COINS${NC}"
  read -r -p "Buy hint? (Y/n): " ans
  ans="$(lc_trim "$ans")"
  if [[ -z "$ans" || "$ans" == "y" || "$ans" == "yes" ]]; then
    PLAYER_COINS=$((PLAYER_COINS - cost))
    echo -e "${CYAN}Hint: $hint_text${NC}"
    save_state "$PLAYER_NAME"
    return 0
  else
    echo "Hint declined."
    return 1
  fi
}

# Save player state
save_state() {
  local name="$1"
  local save_file="${DATA_DIR}/save_${name}.txt"
  cat > "$save_file" <<EOF
PLAYER_NAME=$PLAYER_NAME
PLAYER_LEVEL=$PLAYER_LEVEL
PLAYER_COINS=$PLAYER_COINS
PLAYER_TOKENS=$PLAYER_TOKENS
PLAYER_START_TIME=$PLAYER_START_TIME
PLAYER_STRIKES=$PLAYER_STRIKES
PLAYER_SANDBOX=$PLAYER_SANDBOX
EOF
}

# Load player state
load_state() {
  local name="$1"
  local save_file="${DATA_DIR}/save_${name}.txt"
  if [[ -f "$save_file" ]]; then
    # shellcheck disable=SC1090
    source "$save_file"
    return 0
  else
    return 1
  fi
}

# Admin: reveal answer for level
admin_reveal_answer() {
  local lvl="$1"
  if [[ -z "${LEVEL_NAME[$lvl]}" ]]; then
    echo "Invalid level."
    return
  fi
  echo -e "${BOLD_YELLOW}=== ADMIN: Level $lvl Answers ===${NC}"
  local tasks="${LEVEL_TASK_COUNT[$lvl]}"
  for (( i=1; i<=tasks; i++ )); do
    echo -e "${CYAN}Task $i:${NC} ${LEVEL_TASK_PROMPTS[$lvl,$i]}"
    echo -e "${GREEN}Regex:${NC} ${LEVEL_TASK_REGEX[$lvl,$i]}"
    echo ""
  done
}

# Admin: skip to level
admin_skip_to_level() {
  local new_lvl="$1"
  if [[ -z "${LEVEL_NAME[$new_lvl]}" ]]; then
    echo "Invalid level."
    return
  fi
  PLAYER_LEVEL="$new_lvl"
  echo "Jumped to level $PLAYER_LEVEL."
  save_state "$PLAYER_NAME"
}

# Admin: export clue cards
admin_export_cluecards() {
  local cards_file="${BASE_DIR}/cluecards.txt"
  {
    echo "Treasure Hunt Clue Cards"
    echo "========================="
    for lvl in {1..5}; do
      echo ""
      echo "Level $lvl: ${LEVEL_NAME[$lvl]}"
      echo "Token: ${LEVEL_TOKEN[$lvl]}"
      echo "Reward: ${LEVEL_REWARD[$lvl]} coins"
      echo "Hint Cost: ${LEVEL_HINT_COSTS[$lvl]} coins"
      echo "Hint: ${LEVEL_HINTS[$lvl]}"
      echo ""
      local tasks="${LEVEL_TASK_COUNT[$lvl]}"
      for (( i=1; i<=tasks; i++ )); do
        echo "  Task $i: ${LEVEL_TASK_PROMPTS[$lvl,$i]}"
        echo "  Expected: ${LEVEL_TASK_REGEX[$lvl,$i]}"
        echo ""
      done
    done
  } > "$cards_file"
  echo "Clue cards exported to: $cards_file"
}

# ---------------------------
# Main function
# ---------------------------
main() {
  local admin_mode=false

  # Check for admin flag
  if [[ "${1:-}" == "--admin" ]]; then
    admin_mode=true
    echo -e "${BOLD_MAGENTA}🔐 Admin mode enabled.${NC}"
    # Simple password check
    if [[ -n "${ADMIN_PASS:-}" ]]; then
      read -r -s -p "Admin password: " pass
      echo ""
      if [[ "$pass" != "$ADMIN_PASS" ]]; then
        echo "Incorrect admin password."
        exit 1
      fi
    else
      echo "No ADMIN_PASS env var set. Setting a temporary password for this session."
      read -r -s -p "Set admin password: " pass
      echo ""
      export ADMIN_PASS="$pass"
    fi
  fi

  banner

  # Player name
  echo -n "Enter your player name: "
  read -r pname
  pname="$(lc_trim "$pname")"
  if [[ -z "$pname" ]]; then
    echo "Name cannot be empty. Exiting."
    exit 1
  fi
  PLAYER_NAME="$pname"

  # Check for saved state
  if load_state "$PLAYER_NAME"; then
    echo -e "${GREEN}Welcome back, $PLAYER_NAME! Loaded saved progress.${NC}"
    echo -e "${CYAN}Current level: $PLAYER_LEVEL | Coins: $PLAYER_COINS${NC}"
  else
    echo -e "${GREEN}Welcome, $PLAYER_NAME!${NC}"
    PLAYER_START_TIME="$(date +%s)"
    PLAYER_LEVEL=1
    PLAYER_COINS=$STARTING_COINS
    PLAYER_TOKENS=""
    PLAYER_STRIKES=0
    # Create sandbox
    PLAYER_SANDBOX="${BASE_DIR}/${SANDBOX_PREFIX}_${PLAYER_NAME}"
    mkdir -p "$PLAYER_SANDBOX"
    save_state "$PLAYER_NAME"
  fi

  # Verify sandbox exists
  if [[ ! -d "$PLAYER_SANDBOX" ]]; then
    echo "Creating sandbox directory..."
    PLAYER_SANDBOX="${BASE_DIR}/${SANDBOX_PREFIX}_${PLAYER_NAME}"
    mkdir -p "$PLAYER_SANDBOX"
  fi

  echo -e "${CYAN}Sandbox directory: $PLAYER_SANDBOX${NC}"
  echo -e "${CYAN}You can type: hint | status | inventory | save | quit | help | sandbox${NC}"
  if $admin_mode; then
    echo -e "${MAGENTA}Admin commands: admin:reveal <N> | admin:skip <N> | admin:cluecards${NC}"
  fi
  echo ""

  # Main game loop
  while (( PLAYER_LEVEL <= 5 )); do
    local level_name="${LEVEL_NAME[$PLAYER_LEVEL]}"
    local task_count="${LEVEL_TASK_COUNT[$PLAYER_LEVEL]}"

    echo -e "${BOLD_BLUE}╔═══════════════════════════════════════════════════╗"
    echo -e "║  ${BOLD_WHITE}LEVEL $PLAYER_LEVEL: $level_name"
    echo -e "${BOLD_BLUE}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""

    # Loop through tasks in this level
    for (( step=1; step<=task_count; step++ )); do
      echo -e "${BOLD_CYAN}Task $step/${task_count}:${NC} ${LEVEL_TASK_PROMPTS[$PLAYER_LEVEL,$step]}"

      # Inner loop for user attempts
      while true; do
        echo -n "> "
        read -r user_input_raw

        # Trim input for processing built-in commands
        local user_input
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

        # Use grep for regex matching (more portable than bash [[]])
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
          echo -e "${YELLOW}Expected pattern (regex): ${expected_regex}${NC}"
          PLAYER_STRIKES=$((PLAYER_STRIKES+1))
        fi

        # handle strikes
        if (( PLAYER_STRIKES >= MAX_STRIKES )); then
          echo -e "${YELLOW}You've reached $PLAYER_STRIKES strikes.${NC}"
          if (( PLAYER_COINS >= LEVEL_HINT_COSTS[PLAYER_LEVEL] )); then
            echo "Automatic hint offer after strikes."
            if offer_hint_for_level "$PLAYER_LEVEL"; then
              PLAYER_STRIKES=0
            else
              PLAYER_STRIKES=0
              echo -e "${CYAN}💡 Hint declined. Strikes reset. You can try again!${NC}"
            fi
          else
            echo "Not enough coins for a hint. Consider 'save' and returning later."
            PLAYER_STRIKES=0
            echo -e "${CYAN}💡 Strikes reset. Keep trying!${NC}"
          fi
        fi

        # wrong answer coin penalty
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
  local cert="${BASE_DIR}/certificate_${PLAYER_NAME}.txt"
  {
    echo "Certificate of Completion"
    echo "Player: $PLAYER_NAME"
    echo "Completed: $(date)"
    echo "Elapsed seconds: $elapsed"
    echo "Total coins: $PLAYER_COINS"
    echo "Tokens: $PLAYER_TOKENS"
    echo ""
    echo "Congratulations — you completed the beginner Linux treasure hunt."
  } > "$cert"
  echo "Certificate saved to: $cert"

  echo "Thanks for playing!"
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
