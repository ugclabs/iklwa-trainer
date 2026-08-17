#!/usr/bin/env bash
# Iklwa Terminal Trainer
# Bash-only, stock Kali dependencies. See iklwa-trainer-spec.md for the design.
set -uo pipefail

# Where this script actually lives on disk, independent of the caller's cwd.
# Used only to find infra/iklwa-stage4-network-setup.sh alongside it -- clone,
# chmod, run is the whole distribution story, so this can't assume cwd.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" &>/dev/null && pwd)"

# ============================== Globals ==============================
SCRIPT_VERSION="1.0.0"
REAL_HOME="$HOME"
SANDBOX="$REAL_HOME/iklwa-lab"
FOUND_LOG="$REAL_HOME/iklwa-found-it-log.txt"
GUIDE_HINT="Full walkthrough: see the intern guide that came with this script."

NAME=""
PROGRESS_FILE=""
STAGE=1
STEP=0
SCORE=0
STREAK=0
BEST_STREAK=0
HINTS_USED=0
STAGE1_ELAPSED=0
STAGE2_ELAPSED=0
STAGE3_ELAPSED=0
STAGE4_ELAPSED=0
STAGE_START_EPOCH=0
STAGE_TOTAL=1
declare -a LEARNED_POOL=()

# Stage 4 needs a real lab network to reach. Edit these three to match your
# build -- and keep infra/iklwa-stage4-network-setup.sh and
# infra/iklwa-lab-dnsmasq.conf.example in agreement with them -- see
# iklwa-stage4-network-setup-guide.md. Nothing else in the script needs
# touching. LAB_DNS_IP isn't used in any dig/ping/nmap task itself; it's only
# used to tell whether this machine has already been pointed at the lab.
LAB_DOMAIN="isipingofreight.internal"
LAB_DOWN_HOST="branch-office.isipingofreight.internal"
LAB_DNS_IP="10.0.0.53"

# Overridable so tests can point this somewhere other than the real system
# file. Under normal use this is always /etc/resolv.conf.
IKLWA_RESOLV_CONF="${IKLWA_RESOLV_CONF:-/etc/resolv.conf}"

LAST_CMD=""
LAST_CMD_STATUS=0
CAPTURED_INPUT=""
INTERRUPTED=0
HAS_RUN_SHA256SUM=0
STAGE3_HINT_LEVEL=0

FORCE_STAGE=""
RESET_MODE=""

GREEN="" RED="" ACC="" BOLD="" DIM="" RESET=""
BAR_FULL="#"
BAR_EMPTY="-"

STAGE1_TOTAL=19
STAGE2_TOTAL=10
STAGE4_TOTAL=9

# ============================== Setup helpers ==============================
setup_colors() {
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ -z "${NO_COLOR:-}" ]]; then
    local ncolors
    ncolors=$(tput colors 2>/dev/null || echo 0)
    if [[ "$ncolors" =~ ^[0-9]+$ ]] && (( ncolors >= 8 )); then
      GREEN=$(tput setaf 2); RED=$(tput setaf 1); ACC=$(tput setaf 6)
      BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
    fi
  fi
}

setup_glyphs() {
  local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  if [[ "$loc" == *UTF-8* || "$loc" == *utf8* || "$loc" == *UTF8* ]]; then
    BAR_FULL="█"
    BAR_EMPTY="░"
  fi
}

soft_interrupt() {
  INTERRUPTED=1
  printf "\n%sCtrl+C caught. If you meant to stop a running command, it stopped. Keep going, or type 'quit' to save and leave.%s\n" "${ACC}" "${RESET}"
}

# ============================== Self-check ==============================
selfcheck() {
  local ok=1
  local bins=(grep less head tail wc cat cp mv rm mkdir chmod file du df tar sha256sum tput date sed find dig ping nmap)
  echo "Iklwa Terminal Trainer -- self-check"
  echo
  if (( BASH_VERSINFO[0] < 4 )); then
    echo "  [FAIL] bash version: found ${BASH_VERSION}, need 4.0 or newer"
    ok=0
  else
    echo "  [ OK ] bash version ${BASH_VERSION}"
  fi
  local b
  for b in "${bins[@]}"; do
    if command -v "$b" >/dev/null 2>&1; then
      echo "  [ OK ] $b"
    else
      echo "  [FAIL] $b not found on PATH"
      ok=0
    fi
  done
  if [[ -w "$REAL_HOME" ]]; then
    echo "  [ OK ] home directory is writable"
  else
    echo "  [FAIL] home directory ($REAL_HOME) is not writable"
    ok=0
  fi
  echo
  if (( ok )); then
    echo "All checks passed. Run ./iklwa-trainer.sh to start."
    return 0
  else
    echo "Fix the items above, then re-run --selfcheck."
    return 1
  fi
}

print_banner() {
  cat <<'EOF'

##   ##     ######
##   ##    ##
##   ##    ##  ###
##   ##    ##   ##
 #####      ######

      U G   L A B S
EOF
}

notepad_gate() {
  local tries=0 ans
  echo
  while (( tries < 3 )); do
    read -r -p "Got your notepad and pen ready? This moves fast, and writing commands down as you learn them is how they stick. (Y/n) " ans
    ans="$(trim "${ans:-}")"
    case "$ans" in
      [Yy]|[Yy][Ee][Ss])
        return 0
        ;;
      *)
        ((tries++))
        if (( tries < 3 )); then
          echo "Go grab one -- it's worth it. Ask again when you're back."
        fi
        ;;
    esac
  done
  echo "${DIM}Moving on -- grab one when you can.${RESET}"
}

print_usage() {
  cat <<EOF
Iklwa Terminal Trainer v${SCRIPT_VERSION}

Usage:
  ./iklwa-trainer.sh                start or resume training
  ./iklwa-trainer.sh --stage N      jump straight to stage N (1-4)
  ./iklwa-trainer.sh --reset        wipe your progress, keep the sandbox
  ./iklwa-trainer.sh --reset all    wipe progress and the sandbox
  ./iklwa-trainer.sh --selfcheck    check this machine can run the trainer
  ./iklwa-trainer.sh --help         this message
EOF
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --selfcheck) selfcheck; exit $? ;;
      --help|-h) print_usage; exit 0 ;;
      --stage)
        shift
        FORCE_STAGE="${1:-}"
        [[ "$FORCE_STAGE" =~ ^[1-4]$ ]] || { echo "Usage: --stage 1|2|3|4"; exit 1; }
        ;;
      --reset)
        RESET_MODE="progress"
        if [[ "${2:-}" == "all" ]]; then RESET_MODE="all"; shift; fi
        ;;
      *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
    shift
  done
}

# ============================== Small utilities ==============================
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  s="$(printf '%s' "$s" | tr -s '[:space:]' ' ')"
  printf '%s' "$s"
}

slugify() {
  local s="$1"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  [[ -z "$s" ]] && s="learner"
  printf '%s' "$s"
}

goto() {
  cd "$1" 2>/dev/null || cd "$SANDBOX" 2>/dev/null || true
}

prompt_path() {
  local real_pwd sandbox_real
  real_pwd="$(pwd -P)"
  sandbox_real="$(cd "$SANDBOX" 2>/dev/null && pwd -P)"
  if [[ "$real_pwd" == "$sandbox_real" ]]; then
    printf '~/iklwa-lab'
  else
    printf '~/iklwa-lab/%s' "${real_pwd#"$sandbox_real"/}"
  fi
}

clamp_to_sandbox() {
  local sandbox_real real_pwd
  sandbox_real="$(cd "$SANDBOX" 2>/dev/null && pwd -P)"
  real_pwd="$(pwd -P)"
  case "$real_pwd" in
    "$sandbox_real"|"$sandbox_real"/*) : ;;
    *)
      echo "${RED}That would have taken you outside the lab. Bringing you back to ~/iklwa-lab.${RESET}"
      cd "$SANDBOX" || true
      ;;
  esac
}

# ============================== Dangerous-command guard ==============================
# Prints a short reason and returns 0 if the command is rejected; returns 1 (allowed) otherwise.
guard_reject() {
  local cmd="$1"
  local c
  c="$(printf '%s' "$cmd" | tr -s ' ')"

  if [[ "$c" =~ (^|[[:space:];&|])sudo([[:space:]]|$) ]] || [[ "$c" =~ (^|[[:space:];&|])su([[:space:]]|$) ]]; then
    printf 'sudo/su is not available in here'; return 0
  fi
  if [[ "$c" == *':(){'* ]]; then
    printf 'that pattern is blocked'; return 0
  fi
  if [[ "$c" =~ rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*[[:space:]]+(/|/\*|~|~/\*|\*)([[:space:]]|$) ]]; then
    printf 'recursive delete of a root-level path'; return 0
  fi
  if [[ "$c" =~ \>[[:space:]]*/dev/ ]]; then
    printf 'redirect into /dev'; return 0
  fi
  local word
  for word in $c; do
    if [[ "$word" == /* ]] && [[ "$word" != "$SANDBOX"* ]]; then
      printf 'absolute path outside the lab (%s)' "$word"; return 0
    fi
  done
  return 1
}

# ============================== Input capture ==============================
capture_input() {
  local raw
  while true; do
    INTERRUPTED=0
    if IFS= read -e -r -p "${ACC}$(prompt_path)\$ ${RESET}" raw; then
      CAPTURED_INPUT="$(trim "$raw")"
      return 0
    else
      if (( INTERRUPTED )); then
        INTERRUPTED=0
        continue
      else
        CAPTURED_INPUT=""
        return 1
      fi
    fi
  done
}

graceful_exit() {
  save_progress 2>/dev/null || true
  echo
  echo "${ACC}Progress saved. Come back with the same name to pick up right here.${RESET}"
  exit 0
}

# ============================== Progress + streak ==============================
render_progress() {
  local total="$STAGE_TOTAL"
  (( total < 1 )) && total=1
  local done_n="$STEP"
  local width=20
  local filled=$(( done_n * width / total ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  local bar="" i
  for ((i=0; i<filled; i++)); do bar+="$BAR_FULL"; done
  for ((i=filled; i<width; i++)); do bar+="$BAR_EMPTY"; done
  local elapsed=$(( $(date +%s) - STAGE_START_EPOCH ))
  local mins=$(( elapsed / 60 ))
  printf "%s[%s] %d/%d - streak %d - %dm elapsed%s\n" "$ACC" "$bar" "$done_n" "$total" "$STREAK" "$mins" "$RESET"
}

streak_hit() {
  local pts="${1:-10}"
  ((SCORE += pts))
  ((STREAK++))
  (( STREAK > BEST_STREAK )) && BEST_STREAK=$STREAK
  echo "${GREEN}Nice.${RESET}"
  render_progress
}

streak_break() {
  STREAK=0
  render_progress
}

learn() {
  local cmdname="$1" x found=0
  for x in "${LEARNED_POOL[@]:-}"; do [[ "$x" == "$cmdname" ]] && found=1 && break; done
  (( found )) || LEARNED_POOL+=("$cmdname")
}

# ============================== Teaching primitives ==============================
teach() {
  local cmdname="$1" explanation="$2" analogy="${3:-}"
  echo
  echo "${BOLD}${cmdname}${RESET}"
  echo "$explanation"
  [[ -n "$analogy" ]] && echo "${DIM}${analogy}${RESET}"
}

beat() {
  local prompt_text="$1"
  echo "$prompt_text"
  capture_input || graceful_exit
  echo
}

# Single-shot, atomic, auto-escalating lesson (Stage 1 style).
# task_single <checker_fn> <stronger_hint> <reveal_answer> <points> [flashname]
#
# A command that runs and SUCCEEDS but doesn't satisfy the checker is treated
# as free exploration (the learner looking around, e.g. `ls` mid-`cd`-task) --
# no penalty, no hint escalation, they just see the real output and try again.
# Only a command that genuinely FAILS (non-zero exit) counts as a wrong
# attempt, same as typing `hint`/`help` does explicitly.
task_single() {
  local checker="$1" stronger="$2" reveal="$3" points="${4:-10}" flashname="${5:-}"
  local attempts=0
  while true; do
    capture_input || graceful_exit
    local input="$CAPTURED_INPUT"
    [[ -z "$input" ]] && continue
    case "$input" in
      exit|quit|logout) graceful_exit ;;
    esac
    if [[ "$input" == "hint" || "$input" == "help" ]]; then
      (( attempts < 3 )) && ((attempts++))
    else
      local reason
      if reason="$(guard_reject "$input")"; then
        echo "${RED}Blocked: ${reason}. Not because you did anything wrong -- this script just won't run it.${RESET}"
        continue
      fi
      LAST_CMD="$input"
      history -s -- "$input"
      eval "$input"
      LAST_CMD_STATUS=$?
      clamp_to_sandbox
      if "$checker"; then
        streak_hit "$points"
        return 0
      fi
      if (( LAST_CMD_STATUS != 0 )); then
        ((attempts++))
      else
        continue
      fi
    fi
    case $attempts in
      1) echo "${DIM}Close -- check your spelling. The terminal is fussy about that.${RESET}" ;;
      2) echo "${DIM}Hint: ${stronger}${RESET}" ;;
      *)
        echo "${DIM}${reveal}${RESET}"
        echo "Type it now, yourself:"
        capture_input || graceful_exit
        local retype="$CAPTURED_INPUT"
        if [[ -n "$retype" ]]; then
          local r2
          if ! r2="$(guard_reject "$retype")"; then
            LAST_CMD="$retype"
            history -s -- "$retype"
            eval "$retype"
            LAST_CMD_STATUS=$?
            clamp_to_sandbox
          fi
        fi
        [[ -n "$flashname" ]] && true
        streak_break
        "$checker" && streak_hit "$points"
        return 0
        ;;
    esac
  done
}

# Multi-command, goal-based, no auto-penalty lesson (Stage 2 style). hint is opt-in, free.
# task_multi <checker_fn> <stronger_hint> <reveal_answer> <points>
# task_multi <checker_fn> <stronger_hint> <reveal_answer> <points> [status_fn]
#
# status_fn is optional: for a task made of several independent sub-parts
# (e.g. "make a folder, touch a file, copy a template, make another folder"),
# pass a function that prints a one-line [OK]/[--] checklist of each part.
# It's shown after every command that doesn't yet complete the task, so a
# correctly-done sub-step is visibly acknowledged instead of looking like
# nothing happened -- silence on a multi-part task reads as "it's not
# registering," even when real progress was made.
task_multi() {
  local checker="$1" stronger="$2" reveal="$3" points="${4:-15}" status_fn="${5:-}"
  local hint_level=0
  while true; do
    capture_input || graceful_exit
    local input="$CAPTURED_INPUT"
    if [[ -z "$input" ]]; then
      if "$checker"; then
        streak_hit "$points"
        return 0
      fi
      [[ -n "$status_fn" ]] && "$status_fn"
      continue
    fi
    case "$input" in
      exit|quit|logout) graceful_exit ;;
    esac
    if [[ "$input" == "hint" || "$input" == "help" ]]; then
      ((hint_level++))
      (( hint_level > 3 )) && hint_level=3
      case $hint_level in
        1) echo "${DIM}Think about what you're actually trying to end up with here.${RESET}" ;;
        2) echo "${DIM}${stronger}${RESET}" ;;
        *) echo "${DIM}${reveal}${RESET}" ;;
      esac
      [[ -n "$status_fn" ]] && "$status_fn"
      continue
    fi
    local reason
    if reason="$(guard_reject "$input")"; then
      echo "${RED}Blocked: ${reason}.${RESET}"
      continue
    fi
    LAST_CMD="$input"
    history -s -- "$input"
    eval "$input"
    LAST_CMD_STATUS=$?
    clamp_to_sandbox
    if "$checker"; then
      streak_hit "$points"
      return 0
    elif [[ -n "$status_fn" ]]; then
      "$status_fn"
    fi
  done
}

run_lesson() {
  local idx="$1" fn="$2"
  (( STEP >= idx )) && return 0
  if (( idx <= 19 )); then
    echo "${DIM}[task $idx of $STAGE1_TOTAL]${RESET}"
  else
    echo "${DIM}[block $((idx - 20)) of $STAGE2_TOTAL]${RESET}"
  fi
  "$fn"
  STEP=$idx
  save_progress
}

# ============================== Flashbacks ==============================
flashback_question() {
  local cmdname="$1"
  case "$cmdname" in
    pwd) echo "You're lost. What command shows exactly where you are?"; expect_flashback_answer "pwd" ;;
    ls) echo "You want to see what's in this folder without going anywhere. Command?"; expect_flashback_answer "ls" ;;
    cd) echo "You need to step into a folder called 'evidence'. Command?"; expect_flashback_answer "cd evidence" ;;
    mkdir) echo "You need a brand new folder called 'temp'. Command?"; expect_flashback_answer "mkdir temp" ;;
    cp) echo "Ubuntu Guard rule one: before editing a config, you always...?"; expect_flashback_answer "cp" ;;
    mv) echo "This file is in the wrong place and has the wrong name. One command fixes both. Which?"; expect_flashback_answer "mv" ;;
    rm) echo "You need this file gone, permanently, no bin. Command?"; expect_flashback_answer "rm" ;;
    cat) echo "Short file, you just want to read it in one go. Command?"; expect_flashback_answer "cat" ;;
    less) echo "This file is way too long to dump on screen. What's the rescue?"; expect_flashback_answer "less" ;;
    grep) echo "One line, out of a thousand. What finds it?"; expect_flashback_answer "grep" ;;
    wc) echo "You need a count, not the actual lines. Command?"; expect_flashback_answer "wc -l" ;;
    chmod) echo "scanner.sh won't run. What do you reach for?"; expect_flashback_answer "chmod +x" ;;
    tar) echo "End of shift. Bundle the case folder into one file. Command family?"; expect_flashback_answer "tar" ;;
    sha256sum) echo "Prove the bundle wasn't tampered with in transit. Command?"; expect_flashback_answer "sha256sum" ;;
    *) echo "Quick -- what's the command for '$cmdname' again?"; expect_flashback_answer "$cmdname" ;;
  esac
}

expect_flashback_answer() {
  local accept_pattern="$1"
  local hint_level=0
  while true; do
    capture_input || graceful_exit
    local ans="$CAPTURED_INPUT"
    case "$ans" in
      exit|quit|logout) graceful_exit ;;
    esac
    if [[ "$ans" == "hint" || "$ans" == "help" ]]; then
      ((hint_level++))
      (( hint_level > 3 )) && hint_level=3
      case $hint_level in
        1) echo "${DIM}Think back to which lesson this came from.${RESET}" ;;
        2) echo "${DIM}It starts with '${accept_pattern%% *}'.${RESET}" ;;
        *) echo "${DIM}It's '${accept_pattern}'.${RESET}" ;;
      esac
      continue
    fi
    if [[ "$ans" == *"$accept_pattern"* ]]; then
      echo "${GREEN}Right answer. Moving on.${RESET}"
      ((SCORE += 5))
      return 0
    else
      echo "${DIM}Not quite -- it's '$accept_pattern'. That's what flashbacks are for.${RESET}"
      return 1
    fi
  done
}

maybe_flashback() {
  local pool_size=${#LEARNED_POOL[@]}
  (( pool_size < 2 )) && return 0
  local idx=$(( RANDOM % pool_size ))
  echo
  echo "${BOLD}Flashback --${RESET} quick, before you move on:"
  flashback_question "${LEARNED_POOL[$idx]}"
  echo
}

# ============================== Sandbox ==============================
mkdir_p_if_missing() { [[ -d "$1" ]] || mkdir -p "$1"; }

generate_access_log() {
  local i outcome ip
  for ((i=1; i<=500; i++)); do
    if (( i % 7 == 0 )); then outcome="FAILED"; else outcome="OK"; fi
    ip="10.0.$((i % 50)).$((i % 200))"
    printf '2026-01-%02d %02d:%02d:%02d login attempt from %s -- %s\n' \
      "$(( (i % 28) + 1 ))" "$(( i % 24 ))" "$(( i % 60 ))" "$(( (i*7) % 60 ))" "$ip" "$outcome"
  done
}

build_sandbox() {
  mkdir_p_if_missing "$SANDBOX/cases/acme-corp"
  mkdir_p_if_missing "$SANDBOX/cases/umhlanga-dental"
  mkdir_p_if_missing "$SANDBOX/tools"
  mkdir_p_if_missing "$SANDBOX/usb/client-files"
  mkdir_p_if_missing "$SANDBOX/inbox"

  if [[ ! -f "$SANDBOX/cases/acme-corp/notes.txt" ]]; then
    cat > "$SANDBOX/cases/acme-corp/notes.txt" <<'EOF'
Acme Corp -- initial notes
Client reports slow logins since Tuesday.
Ask reception for the router make and model.
EOF
  fi

  if [[ ! -f "$SANDBOX/cases/acme-corp/access.log" ]]; then
    generate_access_log > "$SANDBOX/cases/acme-corp/access.log"
  fi

  if [[ ! -f "$SANDBOX/cases/acme-corp/config.backup" ]]; then
    cat > "$SANDBOX/cases/acme-corp/config.backup" <<'EOF'
# acme-corp router config (backup)
admin_user=acmeadmin
timeout=300
EOF
  fi

  if [[ ! -f "$SANDBOX/cases/umhlanga-dental/findings.txt" ]]; then
    cat > "$SANDBOX/cases/umhlanga-dental/findings.txt" <<'EOF'
Umhlanga Dental -- findings
Waiting room wifi and admin wifi are on the same network. Flag for separation.
EOF
  fi

  if [[ ! -f "$SANDBOX/tools/scanner.sh" ]]; then
    cat > "$SANDBOX/tools/scanner.sh" <<'EOF'
#!/usr/bin/env bash
echo "scanner.sh: pretend scan complete, 0 issues found."
EOF
    chmod -x "$SANDBOX/tools/scanner.sh" 2>/dev/null || true
  fi

  if [[ ! -f "$SANDBOX/tools/report-template.txt" ]]; then
    cat > "$SANDBOX/tools/report-template.txt" <<'EOF'
Case report template
Client:
Issue:
Findings:
Actions taken:
EOF
  fi

  if [[ ! -f "$SANDBOX/inbox/suspicious.jpg" ]]; then
    cat > "$SANDBOX/inbox/suspicious.jpg" <<'EOF'
This is plain text wearing a .jpg costume. `file` will not be fooled by the extension.
EOF
  fi
}

stage2_seed_usb() {
  mkdir_p_if_missing "$SANDBOX/usb/client-files"
  if [[ ! -f "$SANDBOX/usb/client-files/intake-form.txt" ]]; then
    cat > "$SANDBOX/usb/client-files/intake-form.txt" <<'EOF'
Hillcrest Motors -- intake form
Contact: J. Naidoo
Issue: unauthorised access attempt reported by staff.
EOF
  fi
  if [[ ! -f "$SANDBOX/usb/client-files/photo-evidence.txt" ]]; then
    echo "placeholder for photo evidence log" > "$SANDBOX/usb/client-files/photo-evidence.txt"
  fi
}

stage3_seed_chatsworth() {
  mkdir_p_if_missing "$SANDBOX/usb/chatsworth-logs"
  mkdir_p_if_missing "$SANDBOX/usb/chatsworth-configs"
  if [[ ! -f "$SANDBOX/usb/chatsworth-logs/access.log" ]]; then
    generate_access_log > "$SANDBOX/usb/chatsworth-logs/access.log"
  fi
  if [[ ! -f "$SANDBOX/usb/chatsworth-configs/webserver.conf" ]]; then
    cat > "$SANDBOX/usb/chatsworth-configs/webserver.conf" <<'EOF'
# webserver.conf
listen 443
root /var/www/chatsworth-pharmacy
EOF
  fi
  if [[ ! -f "$SANDBOX/usb/chatsworth-configs/rogue.sh" ]]; then
    cat > "$SANDBOX/usb/chatsworth-configs/rogue.sh" <<'EOF'
#!/usr/bin/env bash
# this file should NOT be executable -- that's the tamper
echo "unexpected script"
EOF
    chmod +x "$SANDBOX/usb/chatsworth-configs/rogue.sh" 2>/dev/null || true
  fi
}

# ============================== Progress persistence ==============================
progress_path_for() {
  printf '%s/.iklwa-trainer-progress-%s' "$REAL_HOME" "$(slugify "$1")"
}

load_progress() {
  PROGRESS_FILE="$(progress_path_for "$NAME")"
  STAGE=1; STEP=0; SCORE=0; STREAK=0; BEST_STREAK=0; HINTS_USED=0
  STAGE1_ELAPSED=0; STAGE2_ELAPSED=0; STAGE3_ELAPSED=0; STAGE4_ELAPSED=0
  LEARNED_POOL=()
  if [[ -f "$PROGRESS_FILE" ]]; then
    local key val
    while IFS='=' read -r key val; do
      case "$key" in
        stage) STAGE="$val" ;;
        step) STEP="$val" ;;
        score) SCORE="$val" ;;
        streak) STREAK="$val" ;;
        best_streak) BEST_STREAK="$val" ;;
        hints_used) HINTS_USED="$val" ;;
        stage1_elapsed) STAGE1_ELAPSED="$val" ;;
        stage2_elapsed) STAGE2_ELAPSED="$val" ;;
        stage3_elapsed) STAGE3_ELAPSED="$val" ;;
        stage4_elapsed) STAGE4_ELAPSED="$val" ;;
        learned)
          IFS=',' read -r -a LEARNED_POOL <<< "$val"
          ;;
      esac
    done < "$PROGRESS_FILE"
    return 0
  fi
  return 1
}

save_progress() {
  {
    echo "name=$NAME"
    echo "stage=$STAGE"
    echo "step=$STEP"
    echo "score=$SCORE"
    echo "streak=$STREAK"
    echo "best_streak=$BEST_STREAK"
    echo "hints_used=$HINTS_USED"
    echo "stage1_elapsed=$STAGE1_ELAPSED"
    echo "stage2_elapsed=$STAGE2_ELAPSED"
    echo "stage3_elapsed=$STAGE3_ELAPSED"
    echo "stage4_elapsed=$STAGE4_ELAPSED"
    local IFS=,
    echo "learned=${LEARNED_POOL[*]:-}"
  } > "$PROGRESS_FILE"
}

handle_reset() {
  local pf
  pf="$(progress_path_for "$NAME")"
  if [[ "$RESET_MODE" == "all" ]]; then
    echo "This deletes ~/iklwa-lab entirely and ${NAME}'s progress. Type the sandbox path to confirm:"
    echo "  $SANDBOX"
    local confirm
    read -r -p "> " confirm
    if [[ "$confirm" == "$SANDBOX" ]]; then
      rm -rf "$SANDBOX"
      rm -f "$pf"
      echo "${GREEN}Sandbox and progress reset.${RESET}"
    else
      echo "Confirmation didn't match. Nothing was deleted."
    fi
  else
    rm -f "$pf"
    echo "${GREEN}${NAME}'s progress reset. Sandbox left as-is.${RESET}"
  fi
}

found_it_log() {
  echo "$(date '+%Y-%m-%d %H:%M'): ${NAME} found the ls sort-by-size flag via --help. Write this into your paper log too." >> "$FOUND_LOG"
}

# ============================== Stage 1: meet every command ==============================
s1_pwd_check() { [[ "${LAST_CMD:-}" =~ ^pwd([[:space:]]|$) ]] && (( LAST_CMD_STATUS == 0 )); }
l_pwd() {
  teach "pwd" "Prints the folder you're standing in right now." "Desktop equivalent: glancing at the window's title bar."
  goto "$SANDBOX/cases"
  echo "You've just been dropped somewhere in the lab. Find out exactly where you are."
  task_single s1_pwd_check "It's three letters, and it means print working directory." "pwd" 10
  learn pwd
  echo "See that path? Every command you run happens *from* here. That's the single most important idea in this course."
}

s1_ls_check() { [[ "${LAST_CMD:-}" =~ ^ls([[:space:]]|$) ]] && (( LAST_CMD_STATUS == 0 )); }
l_ls() {
  teach "ls" "Lists what's in the current folder." "Desktop equivalent: just looking at the window."
  echo "Without going anywhere, see what's actually in this folder."
  task_single s1_ls_check "Two letters. List." "ls" 10
  learn ls
}

s1_cd_cases_check() { [[ "$(pwd -P)" == "$(cd "$SANDBOX/cases" 2>/dev/null && pwd -P)" ]]; }
l_cd_into() {
  goto "$SANDBOX"
  teach "cd folder" "Moves you into a folder." "Desktop equivalent: double-clicking a folder to open it."
  echo "Step into the cases folder."
  task_single s1_cd_cases_check "The command is cd, the folder is right in front of you: cases" "cd cases" 10
  learn cd
}

s1_cd_up_check() { [[ "$(pwd -P)" == "$(cd "$SANDBOX" 2>/dev/null && pwd -P)" ]]; }
l_cd_up() {
  teach "cd .." "Steps back out, one level up." "Desktop equivalent: the back/up arrow in a file browser."
  echo "Now step back out, one level up."
  task_single s1_cd_up_check "Two dots mean 'the folder above this one'." "cd .." 10
}

s1_cd_home_check() { [[ "$(pwd -P)" == "$(cd "$SANDBOX" 2>/dev/null && pwd -P)" ]]; }
l_cd_home() {
  goto "$SANDBOX/cases/acme-corp"
  teach "cd ~" "No matter where you are, jumps straight back to your home base." "Desktop equivalent: the Home shortcut in the sidebar."
  echo "Wherever you are, jump straight back to the top of the lab in one move."
  task_single s1_cd_home_check "The tilde character means home. Just cd, space, tilde." "cd ~" 10
}

s1_mkdir_check() { [[ -d "$SANDBOX/evidence" ]]; }
l_mkdir() {
  teach "mkdir" "Makes a new folder." "Desktop equivalent: right-click, New Folder."
  echo "Make a folder here called evidence."
  task_single s1_mkdir_check "make directory -- the command is literally short for that." "mkdir evidence" 10
  learn mkdir
}

s1_lsl_check() { [[ "${LAST_CMD:-}" =~ ^ls[[:space:]]+-[A-Za-z]*l ]] && (( LAST_CMD_STATUS == 0 )); }
l_lsl() {
  teach "ls -l" "Same command, extra request: list in detail." "A flag is an adverb. ls is 'list'. ls -l is 'list, in detail'."
  echo "List this folder in long detail."
  task_single s1_lsl_check "Add a dash and a lowercase L." "ls -l" 10
}

s1_lsla_check() { [[ "${LAST_CMD:-}" =~ ^ls[[:space:]]+-[A-Za-z]*[la][A-Za-z]*[la] ]] && (( LAST_CMD_STATUS == 0 )); }
l_lsla() {
  teach "ls -la" "Short flags stack. -l and -a together, same as -l -a." "Now also show hidden files, the ones starting with a dot."
  echo "Now do it again, but also show hidden files."
  task_single s1_lsla_check "Two letters after the dash this time: l and a, in either order." "ls -la" 10
  learn ls
}

s1_cp_check() { [[ -f "$SANDBOX/cases/acme-corp/config.working" ]]; }
l_cp() {
  goto "$SANDBOX/cases/acme-corp"
  teach "cp a b" "Copies a file." "Desktop equivalent: copy-paste. Ubuntu Guard rule one: never edit a config directly -- copy it first."
  echo "Copy config.backup to config.working before you touch anything."
  task_single s1_cp_check "cp, then the file you have, then the name you want the copy to have." "cp config.backup config.working" 10
  learn cp
}

s1_mv_check() { [[ -f "$SANDBOX/cases/acme-corp/config-live.working" && ! -f "$SANDBOX/cases/acme-corp/config.working" ]]; }
l_mv() {
  teach "mv a b" "Moves a file. Rename is just a move to a new name in the same place." "Desktop equivalent: drag-and-drop, or Rename."
  echo "Rename config.working to config-live.working."
  task_single s1_mv_check "mv, the old name, the new name." "mv config.working config-live.working" 10
  learn mv
}

s1_rm_check() { [[ ! -f "$SANDBOX/cases/acme-corp/config-live.working" ]]; }
l_rm() {
  teach "rm" "Deletes a file. For good." "Desktop equivalent: nothing, really. There is no bin here."
  echo "Delete config-live.working."
  task_single s1_rm_check "rm, then the file name." "rm config-live.working" 15
  learn rm
  beat "Now try to get it back."
  echo "${DIM}You can't. That's the lesson. There is no undo here.${RESET}"
}

s1_cat_notes_check() { [[ "${LAST_CMD:-}" =~ ^cat[[:space:]].*notes\.txt ]] && (( LAST_CMD_STATUS == 0 )); }
l_cat_notes() {
  teach "cat" "Dumps a whole file straight to the screen." "Fine for short files."
  echo "Read notes.txt in one go."
  task_single s1_cat_notes_check "cat, then the filename." "cat notes.txt" 10
  learn cat
}

s1_cat_flood_check() { [[ "${LAST_CMD:-}" =~ ^cat[[:space:]].*access\.log ]] && (( LAST_CMD_STATUS == 0 )); }
l_cat_flood() {
  echo "Now read the whole access.log file the exact same way."
  task_single s1_cat_flood_check "Same command, different file: cat access.log." "cat access.log" 5
  echo "${DIM}That's 500 lines gone in a blink. cat doesn't care how long a file is.${RESET}"
}

s1_less_check() { [[ "${LAST_CMD:-}" =~ ^less[[:space:]].*access\.log ]] && (( LAST_CMD_STATUS == 0 )); }
l_less() {
  teach "less" "A pager. Shows a file one screen at a time, scrollable. Press q to quit." "The rescue for anything cat floods off your screen."
  echo "Same file, but properly this time."
  task_single s1_less_check "Swap cat for less." "less access.log" 10
  learn less
}

s1_head_check() { [[ "${LAST_CMD:-}" =~ ^head ]] && (( LAST_CMD_STATUS == 0 )); }
l_head() {
  teach "head -20" "Shows just the first lines of a file." ""
  echo "Show only the first 20 lines of access.log."
  task_single s1_head_check "head, the flag -20, then the filename." "head -20 access.log" 10
  learn head
}

s1_tail_check() { [[ "${LAST_CMD:-}" =~ ^tail ]] && (( LAST_CMD_STATUS == 0 )); }
l_tail() {
  teach "tail -20" "Shows just the last lines of a file." ""
  echo "Now show only the last 20 lines."
  task_single s1_tail_check "Same shape, different word: tail -20 access.log." "tail -20 access.log" 10
  learn tail
}

s1_grep_check() { [[ "${LAST_CMD:-}" == *grep* && "${LAST_CMD:-}" == *FAILED* ]] && (( LAST_CMD_STATUS == 0 )); }
l_grep() {
  teach "grep word file" "Finds one line in a thousand." "Search for a word, get back only the lines that contain it."
  echo "Find every line in access.log that contains FAILED."
  task_single s1_grep_check "grep, the word, the filename." "grep FAILED access.log" 15
  learn grep
}

s1_wc_check() { [[ "${LAST_CMD:-}" =~ ^wc[[:space:]]+-l ]] && (( LAST_CMD_STATUS == 0 )); }
l_wc() {
  teach "wc -l" "Counts lines. Doesn't show them, just counts." ""
  echo "Don't read them -- just tell me how many lines access.log has in total."
  task_single s1_wc_check "wc, the flag -l, the filename." "wc -l access.log" 10
  learn wc
}

s1_getting_unstuck() {
  teach "man / --help / which / history" "man opens the manual. --help shows a command's own flags. which tells you where a command lives. history shows what you've typed." "This is how you learn a command nobody taught you."
  echo "${DIM}Try any of them on a command you already know, just to see. Type anything, then Enter.${RESET}"
  capture_input || graceful_exit
  local input="$CAPTURED_INPUT"
  if [[ -n "$input" ]]; then
    local reason
    if ! reason="$(guard_reject "$input")"; then
      LAST_CMD="$input"
      history -s -- "$input"
      eval "$input"
      clamp_to_sandbox
    fi
  fi
  learn man
}

s1_tab_check() { [[ "$(pwd -P)" == "$(cd "$SANDBOX/cases/umhlanga-dental" 2>/dev/null && pwd -P)" ]]; }
l_tab() {
  goto "$SANDBOX/cases"
  teach "Tab completion" "Type the first few letters, press Tab, and the shell finishes the name for you." "Biggest quality-of-life unlock a beginner can get, and nobody ever teaches it properly."
  echo "Get into umhlanga-dental using as few keystrokes as you can: type 'cd um' then press Tab, then Enter."
  task_single s1_tab_check "Type: cd um -- then press the Tab key before hitting Enter." "cd umhlanga-dental" 15
}

s1_history_check() { [[ "${LAST_CMD:-}" =~ ^history([[:space:]]|$) ]] || true; }
l_history_uparrow() {
  teach "history / up arrow" "history lists what you've typed. The up arrow recalls your last command so you can edit and re-run it." ""
  echo "Press the up arrow once to bring back your last command, then just hit Enter."
  echo "${DIM}(If that doesn't feel natural yet, typing 'history' works too.)${RESET}"
  capture_input || graceful_exit
  local input="$CAPTURED_INPUT"
  if [[ -n "$input" ]]; then
    local reason
    if ! reason="$(guard_reject "$input")"; then
      LAST_CMD="$input"
      history -s -- "$input"
      eval "$input"
      clamp_to_sandbox
    fi
  fi
  learn history
}

l_ctrlc_clear() {
  teach "Ctrl+C and clear" "Ctrl+C stops whatever's running right now, without closing your session. clear wipes the screen so you're not scrolling through old output." "The closers. You'll use both constantly."
  echo "Type clear, then Enter, and watch your screen reset."
  capture_input || graceful_exit
  local input="$CAPTURED_INPUT"
  if [[ -n "$input" ]]; then
    local reason
    if ! reason="$(guard_reject "$input")"; then
      LAST_CMD="$input"
      history -s -- "$input"
      eval "$input"
      LAST_CMD_STATUS=$?
      clamp_to_sandbox
    fi
  fi
  learn clear
}

run_stage1() {
  STAGE_START_EPOCH=$(date +%s)
  STAGE_TOTAL=$STAGE1_TOTAL
  echo
  echo "${BOLD}Stage 1 -- meet every command${RESET}"
  run_lesson 1 l_pwd
  run_lesson 2 l_ls
  run_lesson 3 l_cd_into
  run_lesson 4 l_cd_up
  (( STEP == 4 )) && maybe_flashback
  run_lesson 5 l_cd_home
  run_lesson 6 l_mkdir
  run_lesson 7 l_lsl
  run_lesson 8 l_lsla
  (( STEP == 8 )) && maybe_flashback
  run_lesson 9 l_cp
  run_lesson 10 l_mv
  run_lesson 11 l_rm
  run_lesson 12 l_cat_notes
  (( STEP == 12 )) && maybe_flashback
  run_lesson 13 l_cat_flood
  run_lesson 14 l_less
  run_lesson 15 l_head
  run_lesson 16 l_tail
  (( STEP == 16 )) && maybe_flashback
  run_lesson 17 l_grep
  run_lesson 18 l_wc
  goto "$SANDBOX"
  run_lesson 19 l_getting_unstuck
  l_tab
  l_history_uparrow
  l_ctrlc_clear
  STAGE1_ELAPSED=$(( $(date +%s) - STAGE_START_EPOCH ))
  save_progress
}

run_stage1_exit_gate() {
  echo
  echo "${BOLD}Stage 1 checkpoint -- rapid fire.${RESET}"
  local correct=0
  local -a missed=()
  local n=10 i j tmp
  local -a shuffled=("${LEARNED_POOL[@]}")
  (( ${#shuffled[@]} < 1 )) && shuffled=(pwd)
  local pool_size=${#shuffled[@]}
  # Fisher-Yates shuffle so the 10 questions are drawn without replacement --
  # a pool of 10+ learned commands means no repeats at all; a smaller pool
  # cycles through fresh shuffled laps instead of picking randomly with
  # replacement, so no single command can dominate the round.
  for ((i=pool_size-1; i>0; i--)); do
    j=$(( RANDOM % (i+1) ))
    tmp="${shuffled[i]}"; shuffled[i]="${shuffled[j]}"; shuffled[j]="$tmp"
  done
  local -a order=()
  while (( ${#order[@]} < n )); do
    order+=("${shuffled[@]}")
  done
  order=("${order[@]:0:n}")
  local pick
  for pick in "${order[@]}"; do
    if flashback_question "$pick"; then
      ((correct++))
    else
      missed+=("$pick")
    fi
  done
  echo "${BOLD}${correct}/10${RESET}"
  if (( correct >= 8 )); then
    echo "${GREEN}Stage 1 clear.${RESET}"
    return 0
  else
    echo "A short revision lap on what you missed, then we try the checkpoint again."
    local m
    for m in "${missed[@]}"; do
      flashback_question "$m"
    done
    run_stage1_exit_gate
  fi
}

# ============================== Stage 2: a day at Iklwa ==============================
s2b1_check() {
  [[ -d "$SANDBOX/cases/hillcrest-motors" ]] || return 1
  [[ -f "$SANDBOX/cases/hillcrest-motors/notes.txt" ]] || return 1
  [[ -f "$SANDBOX/cases/hillcrest-motors/report-template.txt" ]] || return 1
  [[ -d "$SANDBOX/cases/hillcrest-motors/evidence" ]] || return 1
  return 0
}
s2b1_status() {
  local d1 d2 d3 d4
  [[ -d "$SANDBOX/cases/hillcrest-motors" ]] && d1="${GREEN}[OK]${RESET}" || d1="${RED}[--]${RESET}"
  [[ -f "$SANDBOX/cases/hillcrest-motors/notes.txt" ]] && d2="${GREEN}[OK]${RESET}" || d2="${RED}[--]${RESET}"
  [[ -f "$SANDBOX/cases/hillcrest-motors/report-template.txt" ]] && d3="${GREEN}[OK]${RESET}" || d3="${RED}[--]${RESET}"
  [[ -d "$SANDBOX/cases/hillcrest-motors/evidence" ]] && d4="${GREEN}[OK]${RESET}" || d4="${RED}[--]${RESET}"
  echo "  $d1 case folder    $d2 notes.txt    $d3 report-template.txt copied    $d4 evidence/ folder"
}
b1_morning_setup() {
  goto "$SANDBOX"
  echo
  echo "${BOLD}Block 1 -- morning setup${RESET}"
  echo "You've arrived. New client: Hillcrest Motors. Set up their case folder inside cases/,"
  echo "and put three things in it: an empty notes file, a copy of the report template from"
  echo "tools/, and a subfolder called evidence. Four separate things -- do them in any order,"
  echo "and you'll see which ones are still outstanding after each command."
  teach "touch" "Creates a new, empty file. You'll need it here for the empty notes file." "Desktop equivalent: New > Text Document, but empty."
  task_multi s2b1_check \
    "You need mkdir for the case folder and the evidence subfolder, touch for the empty file, and cp for the template." \
    "mkdir cases/hillcrest-motors && touch cases/hillcrest-motors/notes.txt && cp tools/report-template.txt cases/hillcrest-motors/ && mkdir cases/hillcrest-motors/evidence" \
    20 \
    s2b1_status
  learn touch
}

s2b2_check() { [[ "${LAST_CMD:-}" == ls* ]] && [[ "${LAST_CMD:-}" =~ -[A-Za-z]*S ]] && (( LAST_CMD_STATUS == 0 )); }
b2_flags() {
  echo
  echo "${BOLD}Block 2 -- flags, properly explained${RESET}"
  echo "A command is a verb. A flag is an adverb. ls is 'list'. ls -l is 'list, in detail'."
  echo "Flags are case-sensitive: -s and -S are different requests. Short flags stack: ls -la is ls -l -a."
  echo "--help on any command shows you its flags."
  echo "Find the flag that makes ls sort by file size. I'm not telling you -- use --help."
  task_multi s2b2_check \
    "Run: ls --help   and read the Sort section." \
    "ls -S" \
    20
  found_it_log
  echo "${DIM}Write that into your paper log too -- found it yourself.${RESET}"
}

s2b3a_check() { [[ -x "$SANDBOX/tools/scanner.sh" ]]; }
s2b3b_check() { [[ ! -x "$SANDBOX/tools/scanner.sh" ]]; }
s2b3c_check() { [[ "${LAST_CMD:-}" =~ ^file[[:space:]] ]] && [[ "${LAST_CMD:-}" == *suspicious.jpg* ]] && (( LAST_CMD_STATUS == 0 )); }
b3_permissions() {
  goto "$SANDBOX"
  echo
  echo "${BOLD}Block 3 -- permissions and undoing things${RESET}"
  echo "Try running tools/scanner.sh."
  local reason
  capture_input || graceful_exit
  local input="$CAPTURED_INPUT"
  if [[ -n "$input" ]]; then
    if ! reason="$(guard_reject "$input")"; then
      LAST_CMD="$input"; history -s -- "$input"; eval "$input"; clamp_to_sandbox
    fi
  fi
  echo "${DIM}Permission denied. It exists, but it isn't allowed to run yet.${RESET}"
  teach "chmod +x" "Grants execute permission. Plus is grant, minus is revoke -- that grammar shows up all over Linux." ""
  echo "Fix it, then run it for real."
  task_multi s2b3a_check "chmod, plus x, the file." "chmod +x tools/scanner.sh" 15
  learn chmod
  echo "Now look at ls -l before and after -- see the x appear? Take it back with chmod -x."
  task_multi s2b3b_check "Same shape, minus instead of plus." "chmod -x tools/scanner.sh" 15
  teach "file" "Looks at a file's actual contents, not its name, and tells you what it really is." "Names lie. file doesn't."
  echo "Check inbox/suspicious.jpg with the file command."
  task_multi s2b3c_check "file, then the filename." "file inbox/suspicious.jpg" 15
  learn file
}

s2b4_check() {
  [[ -d "$SANDBOX/cases/hillcrest-motors/client-files" ]] || return 1
  [[ ! -e "$SANDBOX/usb/client-files" ]] || return 1
  return 0
}
s2b4_status() {
  local d1 d2
  [[ -d "$SANDBOX/cases/hillcrest-motors/client-files" ]] && d1="${GREEN}[OK]${RESET}" || d1="${RED}[--]${RESET}"
  [[ ! -e "$SANDBOX/usb/client-files" ]] && d2="${GREEN}[OK]${RESET}" || d2="${RED}[--]${RESET}"
  echo "  $d1 copied into the case folder    $d2 removed from the USB stick"
}
b4_usb_run() {
  goto "$SANDBOX"
  echo
  echo "${BOLD}Block 4 -- the USB run${RESET}"
  echo "The client handed over files on a USB stick, mounted at usb/. Copy the whole"
  echo "client-files folder into the Hillcrest case, confirm it arrived, check how big it"
  echo "is, then delete it from the stick. Two things need to happen -- you'll see which"
  echo "one is still outstanding after each command."
  teach "cp -r / du -sh / df -h / rm -r" "cp alone refuses folders -- you need -r for recursive. du -sh sizes a folder up. df -h shows disk space free. rm -r deletes a folder and everything in it." ""
  task_multi s2b4_check \
    "cp -r for the folder, then rm -r to remove the original from the stick." \
    "cp -r usb/client-files cases/hillcrest-motors/ && rm -r usb/client-files" \
    20 \
    s2b4_status
}

s2b5a_check() { [[ "${LAST_CMD:-}" == *"|"* && "${LAST_CMD:-}" == *grep* && "${LAST_CMD:-}" == *wc* ]] && (( LAST_CMD_STATUS == 0 )); }
s2b5b_check() { [[ -s "$SANDBOX/cases/acme-corp/failed-count.txt" ]]; }
s2b5c_check() { [[ "${LAST_CMD:-}" == *"&&"* ]]; }
b5_joining() {
  goto "$SANDBOX"
  echo
  echo "${BOLD}Block 5 -- joining commands${RESET}"
  teach "|" "The pipe. Real pipe: the output of one command flows straight into the next." "You grep the big log, get a wall of matches. How many is that? You can't tell by eye."
  echo "Count the FAILED lines in cases/acme-corp/access.log in one line, using a pipe."
  task_multi s2b5a_check "grep for FAILED, pipe it into wc -l." "grep FAILED cases/acme-corp/access.log | wc -l" 20
  teach ">" "Redirect. Sends output to a file instead of the screen, so it isn't lost to scroll." ""
  echo "That count just scrolled away. Save it properly this time: cases/acme-corp/failed-count.txt"
  task_multi s2b5b_check "Same pipe as before, but redirect the result into the file with >." "grep FAILED cases/acme-corp/access.log | wc -l > cases/acme-corp/failed-count.txt" 20
  teach "&&" "Do this, and only if it worked, do that. The safe-chaining habit for fieldwork." ""
  echo "Chain two commands safely, as one line: cd into cases/acme-corp, and only if that worked, confirm with pwd."
  task_multi s2b5c_check "Two commands joined by &&." "cd cases/acme-corp && pwd" 20
}

s2b6a_check() { find "$SANDBOX" -maxdepth 3 -iname "*hillcrest*.tar.gz" 2>/dev/null | grep -q .; }
s2b6b_check() { [[ "${LAST_CMD:-}" == sha256sum* ]] && [[ "${LAST_CMD:-}" == *hillcrest-motors.tar.gz* ]] && (( LAST_CMD_STATUS == 0 )); }
b6_end_of_shift() {
  goto "$SANDBOX"
  echo
  echo "${BOLD}Block 6 -- end of shift${RESET}"
  teach "tar -czf" "Bundles a folder into one compressed file." ""
  echo "Bundle the day's case folder, cases/hillcrest-motors, into hillcrest-motors.tar.gz."
  task_multi s2b6a_check "tar, the flags -czf, the output name, then the folder to bundle." "tar -czf hillcrest-motors.tar.gz cases/hillcrest-motors" 20
  teach "sha256sum" "Fingerprints a file. Proof of work -- proof that nothing changed in transit." ""
  echo "Fingerprint the bundle you just made."
  task_multi s2b6b_check "sha256sum, then the bundle's filename." "sha256sum hillcrest-motors.tar.gz" 20
  learn tar
  learn sha256sum
  echo "One more: type history and look back at your whole day."
  task_multi 's2b6c_check' "Just the word history, nothing else." "history" 10
}
s2b6c_check() { [[ "${LAST_CMD:-}" =~ ^history([[:space:]]|$) ]]; }

run_stage2() {
  STAGE_START_EPOCH=$(date +%s)
  STAGE_TOTAL=$STAGE2_TOTAL
  echo
  echo "${BOLD}Stage 2 -- a day at Iklwa${RESET}"
  run_lesson 21 b1_morning_setup
  run_lesson 22 b2_flags
  (( STEP == 22 )) && maybe_flashback
  run_lesson 23 b3_permissions
  run_lesson 24 b4_usb_run
  (( STEP == 24 )) && maybe_flashback
  run_lesson 25 b5_joining
  run_lesson 26 b6_end_of_shift
  STAGE2_ELAPSED=$(( $(date +%s) - STAGE_START_EPOCH ))
  save_progress
}

run_stage2_exit_gate() {
  echo
  echo "${BOLD}Stage 2 checkpoint -- five tasks, goals only, no guidance text.${RESET}"
  mkdir_p_if_missing "$SANDBOX/checkpoint"
  echo "not evidence yet" > "$SANDBOX/checkpoint/draft.txt" 2>/dev/null || true

  goto "$SANDBOX"
  echo "1) Create cases/checkpoint-co/evidence/ and move checkpoint/draft.txt into it, renamed to findings.txt."
  task_multi 'chk1_check' "Think back to block 1." "mkdir -p cases/checkpoint-co/evidence && mv checkpoint/draft.txt cases/checkpoint-co/evidence/findings.txt" 15

  echo "2) Make checkpoint/run.sh executable."
  echo "echo run" > "$SANDBOX/checkpoint/run.sh" 2>/dev/null || true
  task_multi 'chk2_check' "Think back to block 3." "chmod +x checkpoint/run.sh" 15

  echo "3) Count how many lines are in cases/acme-corp/access.log and save the number to cases/checkpoint-co/evidence/linecount.txt."
  task_multi 'chk3_check' "Think back to block 5's redirect." "wc -l cases/acme-corp/access.log > cases/checkpoint-co/evidence/linecount.txt" 15

  echo "4) Bundle cases/checkpoint-co into checkpoint-co.tar.gz."
  task_multi 'chk4_check' "Think back to block 6." "tar -czf checkpoint-co.tar.gz cases/checkpoint-co" 15

  echo "5) Delete the checkpoint folder -- you don't need it anymore."
  task_multi 'chk5_check' "Same as deleting anything else, just with a folder." "rm -r checkpoint" 15

  echo "${GREEN}Checkpoint clear. Stage 3 unlocked.${RESET}"
}
chk1_check() { [[ -f "$SANDBOX/cases/checkpoint-co/evidence/findings.txt" ]]; }
chk2_check() { [[ -x "$SANDBOX/checkpoint/run.sh" ]]; }
chk3_check() { [[ -s "$SANDBOX/cases/checkpoint-co/evidence/linecount.txt" ]]; }
chk4_check() { [[ -f "$SANDBOX/checkpoint-co.tar.gz" ]]; }
chk5_check() { [[ ! -d "$SANDBOX/checkpoint" ]]; }

# ============================== Stage 3: the solo case ==============================
declare -a S3_REQS_DESC=(
  "case folder for Chatsworth Pharmacy under cases/"
  "client files copied off the USB into the case folder"
  "FAILED logins counted and saved as evidence"
  "rogue executable config found and fixed"
  "case bundled with tar"
  "bundle fingerprinted with sha256sum"
)
declare -a S3_REQS_CHECK=(s3_check_casefolder s3_check_usbcopy s3_check_evidence s3_check_permfix s3_check_tar s3_check_sum)
declare -a S3_REQS_CONCEPT=(
  "mkdir makes a new folder. Where do the other cases live?"
  "cp -r moves a whole folder's contents, not just one file."
  "grep finds matching lines, wc -l counts them, and > saves output to a file instead of the screen."
  "ls -l shows permissions. chmod -x removes the execute bit."
  "tar -czf bundles a folder into one file."
  "sha256sum fingerprints a file so you can prove it wasn't changed."
)
declare -a S3_REQS_ANSWER=(
  "mkdir cases/chatsworth-pharmacy"
  "cp -r usb/chatsworth-logs cases/chatsworth-pharmacy/ && cp -r usb/chatsworth-configs cases/chatsworth-pharmacy/"
  "grep FAILED cases/chatsworth-pharmacy/chatsworth-logs/access.log | wc -l > cases/chatsworth-pharmacy/evidence-failed-count.txt"
  "chmod -x cases/chatsworth-pharmacy/chatsworth-configs/rogue.sh"
  "tar -czf chatsworth-pharmacy.tar.gz cases/chatsworth-pharmacy"
  "sha256sum chatsworth-pharmacy.tar.gz"
)

s3_check_casefolder() { [[ -d "$SANDBOX/cases/chatsworth-pharmacy" ]]; }
s3_check_usbcopy() {
  [[ -d "$SANDBOX/cases/chatsworth-pharmacy" ]] || return 1
  find "$SANDBOX/cases/chatsworth-pharmacy" -iname "*.log" 2>/dev/null | grep -q . || return 1
  find "$SANDBOX/cases/chatsworth-pharmacy" \( -iname "*.conf" -o -iname "rogue.sh" \) 2>/dev/null | grep -q .
}
s3_check_evidence() {
  local f
  for f in "$SANDBOX/cases/chatsworth-pharmacy"/*failed* "$SANDBOX/cases/chatsworth-pharmacy"/*evidence*; do
    [[ -s "$f" ]] && return 0
  done
  return 1
}
s3_check_permfix() {
  local f
  f=$(find "$SANDBOX/cases/chatsworth-pharmacy" -iname "rogue.sh" 2>/dev/null | head -1)
  [[ -n "$f" ]] || return 1
  [[ ! -x "$f" ]]
}
s3_check_tar() { find "$SANDBOX" -maxdepth 3 -iname "*chatsworth*.tar.gz" 2>/dev/null | grep -q .; }
s3_check_sum() {
  local tarball
  tarball=$(find "$SANDBOX" -maxdepth 3 -iname "*chatsworth*.tar.gz" 2>/dev/null | head -1)
  [[ -n "$tarball" ]] || return 1
  [[ -f "${tarball}.sha256" ]] && return 0
  [[ "${HAS_RUN_SHA256SUM:-0}" == "1" ]]
}

give_stage3_hint() {
  local first_missing=-1 i
  for i in "${!S3_REQS_CHECK[@]}"; do
    if ! "${S3_REQS_CHECK[$i]}"; then first_missing=$i; break; fi
  done
  if (( first_missing == -1 )); then
    echo "${GREEN}Everything's checking out so far. Type 'done' when you're ready.${RESET}"
    return
  fi
  ((STAGE3_HINT_LEVEL++))
  (( STAGE3_HINT_LEVEL > 3 )) && STAGE3_HINT_LEVEL=3
  ((HINTS_USED++))
  ((SCORE -= 5))
  case $STAGE3_HINT_LEVEL in
    1) echo "${DIM}Think about which block of stage 2 this looked like.${RESET}" ;;
    2) echo "${DIM}${S3_REQS_CONCEPT[$first_missing]}${RESET}" ;;
    *) echo "${DIM}${S3_REQS_ANSWER[$first_missing]}${RESET}"; echo "Type it yourself." ;;
  esac
  save_progress
}

stage3_audit_report() {
  local plain="${1:-0}" i ok=0 tick cross
  if (( plain )); then tick="[OK]"; cross="[--]"; else tick="${GREEN}[OK]${RESET}"; cross="${RED}[--]${RESET}"; fi
  ok=1
  for i in "${!S3_REQS_CHECK[@]}"; do
    if "${S3_REQS_CHECK[$i]}"; then
      echo "  $tick ${S3_REQS_DESC[$i]}"
    else
      echo "  $cross ${S3_REQS_DESC[$i]}"
      ok=0
    fi
  done
  return $(( ok ? 0 : 1 ))
}

build_submission_bundle() {
  local ts slug work out
  ts="$(date +%Y%m%d-%H%M%S)"
  slug="$(slugify "$NAME")"
  work="$(mktemp -d)"
  mkdir -p "$work/submission/sandbox-snapshot"
  stage3_audit_report 1 > "$work/submission/audit-result.txt"
  {
    echo "Learner: $NAME"
    echo "Generated: $(date)"
    echo "Score: $SCORE"
    echo "Hints used: $HINTS_USED"
    echo "Best streak: $BEST_STREAK"
    echo "Stage 1 time (s): $STAGE1_ELAPSED"
    echo "Stage 2 time (s): $STAGE2_ELAPSED"
  } > "$work/submission/session-summary.txt"
  cp -r "$SANDBOX"/. "$work/submission/sandbox-snapshot/" 2>/dev/null
  out="$REAL_HOME/iklwa-submission-${slug}-${ts}.tar.gz"
  tar -czf "$out" -C "$work" submission
  rm -rf "$work"
  echo
  echo "${GREEN}Submission bundle written:${RESET} $out"
  echo "Copy this file to USB and hand it in for review."
}

run_stage3_audit() {
  echo "${BOLD}Case audit${RESET}"
  if stage3_audit_report 0; then
    echo
    echo "${GREEN}Case complete.${RESET} Building your submission bundle..."
    build_submission_bundle
    return 0
  else
    echo
    echo "Not quite -- fix what's marked [--] and type 'done' again."
    return 1
  fi
}

run_stage3() {
  STAGE_START_EPOCH=$(date +%s)
  STAGE_TOTAL=1
  echo
  echo "${BOLD}Stage 3 -- the solo case${RESET}"
  cat <<'EOF'
Client: Chatsworth Pharmacy. They suspect someone tampered with their web
server config last night. On the USB (usb/) you will find last night's server
logs and a folder of configs.

Your tasking: set up the case properly, get the material off the stick, find
every FAILED login in the logs and how many there were, save that as evidence,
check whether any config file is executable when it should not be and fix it,
then bundle and fingerprint the whole case for hand-in.

Work clean. Type 'done' when you believe you're done. Type 'hint' if stuck.
EOF
  stage3_seed_chatsworth
  goto "$SANDBOX"
  STAGE3_HINT_LEVEL=0
  while true; do
    capture_input || graceful_exit
    local input="$CAPTURED_INPUT"
    [[ -z "$input" ]] && continue
    case "$input" in
      exit|quit|logout) graceful_exit ;;
      hint|help) give_stage3_hint; continue ;;
      done)
        if run_stage3_audit; then
          STAGE3_ELAPSED=$(( $(date +%s) - STAGE_START_EPOCH ))
          STAGE=4
          STEP=0
          save_progress
          return 0
        fi
        continue
        ;;
    esac
    local reason
    if reason="$(guard_reject "$input")"; then
      echo "${RED}Blocked: ${reason}.${RESET}"
      continue
    fi
    LAST_CMD="$input"
    history -s -- "$input"
    eval "$input"
    LAST_CMD_STATUS=$?
    clamp_to_sandbox
    [[ "$input" == sha256sum* && "$LAST_CMD_STATUS" -eq 0 ]] && HAS_RUN_SHA256SUM=1
    STAGE3_HINT_LEVEL=0
  done
}

# ============================== Stage 4: recon day ==============================
# Unlike stages 1-3, stage 4 needs a real lab network to reach -- dig, ping,
# and nmap have nothing to check against without one. s4_check_network is a
# preflight gate: if the lab domain doesn't resolve, stage 4 bails cleanly
# before any task starts, tells the learner what to do about it, and leaves
# STAGE/STEP untouched so re-running the trainer lands right back here once
# the network's actually up. See iklwa-stage4-network-setup-guide.md.
s4_check_network() {
  command -v dig >/dev/null 2>&1 || return 1
  local ans
  ans="$(dig +short +time=3 +tries=1 "$LAB_DOMAIN" 2>/dev/null)"
  [[ -n "$ans" ]]
}

# True if this machine's resolver is already pointed at the lab (a
# "nameserver $LAB_DNS_IP" line in resolv.conf). Tells apart two different
# reasons s4_check_network can fail: this box has never been set up (worth
# fixing automatically, see s4_auto_network_setup below), versus it's already
# pointed at the lab and the lab server itself just isn't answering right now
# (a resolver rewrite wouldn't help, so don't offer one).
s4_resolver_points_at_lab() {
  grep -qs "^nameserver[[:space:]]\+${LAB_DNS_IP}\$" "$IKLWA_RESOLV_CONF" 2>/dev/null
}

# Stage 4's one deliberate, explained exception to "the trainer never needs
# root." Runs the companion setup script via sudo so a learner never has to
# know that script exists or run it themselves -- clone, chmod, run the
# trainer is the whole flow, first time through stage 4 included. Everything
# else in this trainer runs as the learner's own user; this is the one place
# that doesn't, and it says so before asking for the password.
s4_auto_network_setup() {
  local setup_script="$SCRIPT_DIR/infra/iklwa-stage4-network-setup.sh"
  [[ -f "$setup_script" ]] || return 1
  echo
  echo "${BOLD}This machine hasn't been pointed at the lab network yet.${RESET}"
  echo "That's a one-time fix -- point this box's DNS resolver at the lab server. It needs"
  echo "root, so you're about to get a sudo password prompt."
  echo
  sudo bash "$setup_script"
}

s4_case_check() { [[ -d "$SANDBOX/cases/isipingo-freight" ]] && [[ -d "$SANDBOX/cases/isipingo-freight/evidence" ]]; }
l_s4_case_setup() {
  goto "$SANDBOX"
  echo
  echo "${BOLD}Stage 4 -- recon day${RESET}"
  echo "New client: Isipingo Freight. Before Ubuntu Guard ever touches a client's network for"
  echo "real, you look at it from outside first. Set up their case folder the way you always do."
  task_single s4_case_check "Same shape as every other case folder, plus its evidence subfolder." "mkdir -p cases/isipingo-freight/evidence" 15
}

s4_dns_a_check() {
  local lc="${LAST_CMD,,}"
  [[ "$lc" =~ ^dig[[:space:]] ]] || return 1
  [[ "$lc" == *"${LAB_DOMAIN,,}"* ]] || return 1
  [[ "$lc" =~ [[:space:]](mx|txt|ns|cname)([[:space:]]|$) ]] && return 1
  [[ -s "$SANDBOX/cases/isipingo-freight/evidence/dns-a.txt" ]]
}
l_s4_dns_a() {
  teach "dig domain TYPE" "Looks up a specific kind of DNS record for a domain. An A record gives you an address." "No desktop equivalent for this one -- it's the internet's own phone book, and there's no icon for it."
  echo "Isipingo Freight's domain is ${BOLD}${LAB_DOMAIN}${RESET}. Look up its main address record and save what you find: cases/isipingo-freight/evidence/dns-a.txt"
  task_single s4_dns_a_check "dig, the domain, redirect the result into the evidence file." "dig ${LAB_DOMAIN} A > cases/isipingo-freight/evidence/dns-a.txt" 15
  learn dig
}

s4_dns_mx_check() {
  local lc="${LAST_CMD,,}"
  [[ "$lc" =~ ^dig[[:space:]] ]] || return 1
  [[ "$lc" == *"${LAB_DOMAIN,,}"* ]] || return 1
  [[ "$lc" =~ [[:space:]]mx([[:space:]]|$) ]] || return 1
  [[ -s "$SANDBOX/cases/isipingo-freight/evidence/dns-mx.txt" ]]
}
l_s4_dns_mx() {
  teach "MX record" "Where a domain's mail actually goes." ""
  echo "Same domain, different question: where does their mail go? Save it as dns-mx.txt."
  task_single s4_dns_mx_check "Same shape as before, swap the type." "dig ${LAB_DOMAIN} MX > cases/isipingo-freight/evidence/dns-mx.txt" 15
}

s4_dns_txt_check() {
  local lc="${LAST_CMD,,}"
  [[ "$lc" =~ ^dig[[:space:]] ]] || return 1
  [[ "$lc" == *"${LAB_DOMAIN,,}"* ]] || return 1
  [[ "$lc" =~ [[:space:]]txt([[:space:]]|$) ]] || return 1
  [[ -s "$SANDBOX/cases/isipingo-freight/evidence/dns-txt.txt" ]]
}
l_s4_dns_txt() {
  teach "TXT record" "A free-text note attached to a domain. Sometimes a real config note gets left in one, on purpose or not." ""
  echo "Check what note, if any, is sitting in their TXT record. Save it as dns-txt.txt."
  task_single s4_dns_txt_check "Same shape again, type TXT." "dig ${LAB_DOMAIN} TXT > cases/isipingo-freight/evidence/dns-txt.txt" 15
  echo "${DIM}Read what came back. Whatever's in there isn't decoration -- someone left it on purpose.${RESET}"
}

s4_dns_ns_check() {
  local lc="${LAST_CMD,,}"
  [[ "$lc" =~ ^dig[[:space:]] ]] || return 1
  [[ "$lc" == *"${LAB_DOMAIN,,}"* ]] || return 1
  [[ "$lc" =~ [[:space:]]ns([[:space:]]|$) ]] || return 1
  [[ -s "$SANDBOX/cases/isipingo-freight/evidence/dns-ns.txt" ]]
}
l_s4_dns_ns() {
  teach "NS record" "Says which server is actually authoritative for a domain -- who's allowed to answer for it." ""
  echo "Find out who's authoritative for ${LAB_DOMAIN}. Save it as dns-ns.txt."
  task_single s4_dns_ns_check "Same shape, type NS." "dig ${LAB_DOMAIN} NS > cases/isipingo-freight/evidence/dns-ns.txt" 15
  echo "${DIM}One nameserver in a lab this size isn't unusual. A real client with none listed would be a real problem.${RESET}"
}

s4_dns_cname_check() {
  local lc="${LAST_CMD,,}"
  [[ "$lc" =~ ^dig[[:space:]] ]] || return 1
  [[ "$lc" == *"www.${LAB_DOMAIN,,}"* ]] || return 1
  [[ "$lc" =~ [[:space:]]cname([[:space:]]|$) ]] || return 1
  [[ -s "$SANDBOX/cases/isipingo-freight/evidence/dns-cname.txt" ]]
}
l_s4_dns_cname() {
  teach "CNAME record" "An alias -- one name pointing at another name, not directly at an address." ""
  echo "Their website is at www.${LAB_DOMAIN}, but that's not where the address actually lives. Find out what it's an alias for. Save it as dns-cname.txt."
  task_single s4_dns_cname_check "Query the www name specifically, type CNAME." "dig www.${LAB_DOMAIN} CNAME > cases/isipingo-freight/evidence/dns-cname.txt" 15
}

s4_ping_up_check() {
  [[ "${LAST_CMD:-}" =~ ^ping[[:space:]] ]] || return 1
  [[ "${LAST_CMD:-}" == *"-c"* ]] || return 1
  [[ "${LAST_CMD:-}" == *"$LAB_DOMAIN"* ]] || return 1
  [[ "${LAST_CMD:-}" != *"$LAB_DOWN_HOST"* ]] || return 1
  (( LAST_CMD_STATUS == 0 ))
}
l_s4_ping_up() {
  teach "ping -c N" "Sends N pings and stops. Never run ping bare in here -- without -c it never stops on its own; Ctrl+C gets you out if you do." "No desktop equivalent really -- closest is a router's own connectivity light."
  echo "Ping their main address, 3 times, and see if it actually answers."
  task_single s4_ping_up_check "ping, -c 3, then the domain." "ping -c 3 ${LAB_DOMAIN}" 15
  learn ping
}

s4_ping_down_check() {
  [[ "${LAST_CMD:-}" =~ ^ping[[:space:]] ]] || return 1
  [[ "${LAST_CMD:-}" == *"-c"* ]] || return 1
  [[ "${LAST_CMD:-}" == *"$LAB_DOWN_HOST"* ]] || return 1
  return 0
}
l_s4_ping_down() {
  echo "Now their branch office: ${LAB_DOWN_HOST}. Same three pings."
  task_single s4_ping_down_check "Same shape, different host." "ping -c 3 ${LAB_DOWN_HOST}" 15
  echo "${DIM}No answer isn't a broken command -- it's a finding. That's the one you'd flag before ever touching their network for real.${RESET}"
}

s4_nmap_check() {
  [[ "${LAST_CMD:-}" =~ ^nmap[[:space:]] ]] || return 1
  [[ "${LAST_CMD:-}" == *"$LAB_DOMAIN"* ]] || return 1
  [[ -s "$SANDBOX/cases/isipingo-freight/evidence/portscan.txt" ]]
}
l_s4_nmap() {
  teach "nmap --top-ports N" "Checks the N most common ports on a target and tells you what's actually open." "A full scan checks all 65535 -- you almost never need that, and it's slow. Top ports first, always."
  echo "Run a quick scan against ${LAB_DOMAIN} and save what's open: cases/isipingo-freight/evidence/portscan.txt"
  task_single s4_nmap_check "nmap, --top-ports 20, the domain, redirect into the evidence file." "nmap --top-ports 20 ${LAB_DOMAIN} > cases/isipingo-freight/evidence/portscan.txt" 20
  learn nmap
}

run_stage4() {
  STAGE_START_EPOCH=$(date +%s)
  STAGE_TOTAL=$STAGE4_TOTAL
  if ! s4_check_network; then
    if s4_resolver_points_at_lab; then
      echo
      echo "${RED}Can't reach the lab network yet.${RESET}"
      echo "This machine's already pointed at the lab server, but it isn't answering right now."
      echo "Ask your supervisor to check it's up, then just run the trainer again."
      echo "${DIM}Nothing's lost -- just run the trainer again once that's sorted, and you'll land right back here.${RESET}"
      return 1
    fi
    if s4_auto_network_setup && s4_check_network; then
      echo
      echo "${GREEN}Network's set up.${RESET} Continuing into stage 4."
    else
      echo
      echo "${RED}Couldn't reach the lab network yet.${RESET}"
      echo "Either that sudo step didn't go through, or the lab server itself isn't up yet."
      echo "Ask your supervisor to check, then just run the trainer again."
      echo "${DIM}Nothing's lost -- just run the trainer again once that's sorted, and you'll land right back here.${RESET}"
      return 1
    fi
  fi
  echo
  echo "${BOLD}Stage 4 -- recon day${RESET}"
  run_lesson 1 l_s4_case_setup
  run_lesson 2 l_s4_dns_a
  run_lesson 3 l_s4_dns_mx
  run_lesson 4 l_s4_dns_txt
  run_lesson 5 l_s4_dns_ns
  run_lesson 6 l_s4_dns_cname
  run_lesson 7 l_s4_ping_up
  run_lesson 8 l_s4_ping_down
  run_lesson 9 l_s4_nmap
  STAGE4_ELAPSED=$(( $(date +%s) - STAGE_START_EPOCH ))
  save_progress
  echo
  echo "${GREEN}Stage 4 clear.${RESET} Recon day done."
  return 0
}

# ============================== Main ==============================
prompt_for_name() {
  local n
  read -r -p "What's your name? " n
  n="$(trim "$n")"
  [[ -z "$n" ]] && n="learner"
  NAME="$n"
}

main() {
  parse_args "$@"
  setup_colors
  setup_glyphs
  trap soft_interrupt SIGINT

  print_banner
  echo "${BOLD}Iklwa Terminal Trainer${RESET}  (v${SCRIPT_VERSION})"
  echo "$GUIDE_HINT"
  echo "Type ${BOLD}help${RESET} or ${BOLD}hint${RESET} any time you're stuck. Type ${BOLD}quit${RESET} any time to save and leave."
  notepad_gate
  echo

  prompt_for_name

  if [[ -n "$RESET_MODE" ]]; then
    handle_reset
  fi

  if ! load_progress; then
    STAGE=1; STEP=0
  fi
  if [[ -n "$FORCE_STAGE" ]]; then
    STAGE="$FORCE_STAGE"
    STEP=0
  fi

  build_sandbox

  echo
  if (( STEP > 0 || STAGE > 1 )); then
    echo "Welcome back, ${BOLD}${NAME}${RESET}. Resuming at stage ${STAGE}."
  else
    echo "Hi ${BOLD}${NAME}${RESET}. Let's get you lost in a folder tree on purpose."
  fi
  save_progress

  export HOME="$SANDBOX"
  goto "$SANDBOX"

  if (( STAGE == 1 )); then
    run_stage1
    run_stage1_exit_gate
    STAGE=2
    STEP=0
    save_progress
  fi

  if (( STAGE == 2 )); then
    stage2_seed_usb
    run_stage2
    run_stage2_exit_gate
    STAGE=3
    STEP=0
    save_progress
  fi

  if (( STAGE == 3 )); then
    run_stage3
  fi

  if (( STAGE == 4 )); then
    if run_stage4; then
      STAGE=5
      STEP=0
      save_progress
    fi
  fi

  if (( STAGE >= 5 )); then
    echo
    echo "${GREEN}All four stages complete.${RESET} Personal best streak: ${BEST_STREAK}. Score: ${SCORE}."
    echo "Run ./iklwa-trainer.sh --stage 3 any time to attempt the solo case again, cold."
    echo "Run ./iklwa-trainer.sh --stage 4 any time to re-run recon day."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
