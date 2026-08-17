#!/usr/bin/env bash
# Regression test for iklwa-trainer.sh. Run this after any edit to the trainer
# to confirm every lesson/block/case-requirement answer still satisfies its
# own checker, the guard still blocks dangerous input, and progress/reset/
# submission-bundle plumbing still works. Safe to run anywhere -- it uses a
# throwaway $HOME and never touches your real sandbox or progress files.
set -u
cd "$(dirname "$0")"
export HOME="/tmp/iklwa-selftest-home"
rm -rf "$HOME"
mkdir -p "$HOME"

source ./iklwa-trainer.sh
setup_colors
setup_glyphs
NAME="Self Test"

PASS=0
FAIL=0
check() {
  local desc="$1" cond="$2"
  if eval "$cond"; then
    echo "  [PASS] $desc"
    ((PASS++))
  else
    echo "  [FAIL] $desc"
    ((FAIL++))
  fi
}

echo "== Sandbox build + idempotency =="
build_sandbox
echo "custom marker" > "$SANDBOX/cases/acme-corp/notes.txt"
build_sandbox
check "idempotent build does not clobber existing file" '[[ "$(cat "$SANDBOX/cases/acme-corp/notes.txt")" == "custom marker" ]]'
check "access.log has 500 lines" '[[ "$(wc -l < "$SANDBOX/cases/acme-corp/access.log")" -eq 500 ]]'
FAILED_COUNT=$(grep -c FAILED "$SANDBOX/cases/acme-corp/access.log")
check "access.log has a meaningful number of FAILED lines (got $FAILED_COUNT)" '(( FAILED_COUNT > 20 && FAILED_COUNT < 200 ))'

echo
echo "== Guard =="
check "guard rejects sudo" 'guard_reject "sudo whoami" >/dev/null'
check "guard rejects rm -rf /" 'guard_reject "rm -rf /" >/dev/null'
check "guard allows ls -la" '! guard_reject "ls -la" >/dev/null'

echo
echo "== Stage 1 lesson answers satisfy their own checkers =="
export HOME="$SANDBOX"   # main() does this before stages start; replicate it here
goto "$SANDBOX"
run_check() {
  local label="$1" cmd="$2" checker="$3"
  LAST_CMD="$cmd"
  eval "$cmd" >/dev/null 2>&1
  LAST_CMD_STATUS=$?
  check "$label ('$cmd')" "$checker"
}
run_check_fails() {
  # Same as run_check, but asserts the checker correctly REJECTS a bad attempt
  # (e.g. right command, wrong directory) -- the inverse of run_check.
  local label="$1" cmd="$2" checker="$3"
  LAST_CMD="$cmd"
  eval "$cmd" >/dev/null 2>&1
  LAST_CMD_STATUS=$?
  check "$label ('$cmd') correctly fails" "! $checker"
}

goto "$SANDBOX/cases"
run_check "pwd"      "pwd"                                  's1_pwd_check'
run_check "ls"        "ls"                                   's1_ls_check'
goto "$SANDBOX"
run_check "cd cases"  "cd cases"                              's1_cd_cases_check'
run_check "cd .."     "cd .."                                 's1_cd_up_check'
run_check "cd ~"      "cd ~"                                  's1_cd_home_check'
run_check "mkdir"     "mkdir evidence"                        's1_mkdir_check'
run_check "ls -l"     "ls -l"                                 's1_lsl_check'
run_check "ls -la"    "ls -la"                                's1_lsla_check'
goto "$SANDBOX/cases/acme-corp"
run_check "cp"        "cp config.backup config.working"       's1_cp_check'
run_check "mv"        "mv config.working config-live.working" 's1_mv_check'
run_check "rm"        "rm config-live.working"                's1_rm_check'
run_check "cat notes" "cat notes.txt"                         's1_cat_notes_check'
run_check "cat flood" "cat access.log"                        's1_cat_flood_check' >/dev/null
run_check "less"      "less access.log"                       's1_less_check' >/dev/null
run_check "head"      "head -20 access.log"                   's1_head_check'
run_check "tail"      "tail -20 access.log"                   's1_tail_check'
run_check "grep"      "grep FAILED access.log"                's1_grep_check' >/dev/null
run_check "wc -l"     "wc -l access.log"                      's1_wc_check'
goto "$SANDBOX/cases"
run_check "tab-equiv" "cd umhlanga-dental"                    's1_tab_check'

echo
echo "== Regression: right command, wrong folder must NOT pass (reported bug) =="
goto "$SANDBOX/cases/umhlanga-dental"   # access.log does not exist here
run_check_fails "grep from wrong folder"  "grep FAILED access.log"  's1_grep_check'
run_check_fails "cat from wrong folder"   "cat access.log"          's1_cat_flood_check'
run_check_fails "wc -l from wrong folder" "wc -l access.log"        's1_wc_check'
run_check_fails "head from wrong folder"  "head -20 access.log"     's1_head_check'
run_check_fails "tail from wrong folder"  "tail -20 access.log"     's1_tail_check'
goto "$SANDBOX/cases/acme-corp"   # restore position for the rest of the suite

echo
echo "== Regression: exploring with a harmless command must not be graded as an attempt =="
goto "$SANDBOX"
rm -rf "$SANDBOX/evidence" 2>/dev/null
LAST_CMD="ls"; eval "ls" >/dev/null 2>&1; LAST_CMD_STATUS=$?
check "harmless 'ls' exploration succeeds (exit 0), so task_single would not penalize it" '[[ "$LAST_CMD_STATUS" -eq 0 ]]'
check "...and correctly does NOT satisfy an unrelated checker (e.g. the mkdir task)" '! s1_mkdir_check'
goto "$SANDBOX/cases/acme-corp"

echo
echo "== Stage 2 block answers satisfy their own checkers =="
goto "$SANDBOX"
run_check "b1 setup" "mkdir cases/hillcrest-motors && touch cases/hillcrest-motors/notes.txt && cp tools/report-template.txt cases/hillcrest-motors/ && mkdir cases/hillcrest-motors/evidence" 's2b1_check'
run_check "b2 flags" "ls -S" 's2b2_check'
run_check "b3a chmod+x" "chmod +x tools/scanner.sh" 's2b3a_check'
run_check "b3b chmod-x" "chmod -x tools/scanner.sh" 's2b3b_check'
run_check "b3c file"    "file inbox/suspicious.jpg" 's2b3c_check'
stage2_seed_usb
run_check "b4 usb run" "cp -r usb/client-files cases/hillcrest-motors/ && rm -r usb/client-files" 's2b4_check'
run_check "b5a pipe"   "grep FAILED cases/acme-corp/access.log | wc -l" 's2b5a_check'
run_check "b5b redirect" "grep FAILED cases/acme-corp/access.log | wc -l > cases/acme-corp/failed-count.txt" 's2b5b_check'
run_check "b5c &&"     "cd cases/acme-corp && pwd" 's2b5c_check'
goto "$SANDBOX"
run_check "b6a tar"    "tar -czf hillcrest-motors.tar.gz cases/hillcrest-motors" 's2b6a_check'
run_check "b6b sha256sum" "sha256sum hillcrest-motors.tar.gz" 's2b6b_check'

echo
echo "== Stage 3 requirement answers satisfy their own checkers =="
goto "$SANDBOX"
stage3_seed_chatsworth
for i in "${!S3_REQS_ANSWER[@]}"; do
  LAST_CMD="${S3_REQS_ANSWER[$i]}"
  eval "$LAST_CMD" >/dev/null 2>&1
  [[ "$LAST_CMD" == sha256sum* ]] && HAS_RUN_SHA256SUM=1
  check "s3 req $((i+1)): ${S3_REQS_DESC[$i]}" "${S3_REQS_CHECK[$i]}"
done

echo
echo "== Full stage3 audit + submission bundle =="
if stage3_audit_report 1 >/tmp/audit_out.txt; then
  echo "  [PASS] full audit passes after all answers applied"
  ((PASS++))
else
  echo "  [FAIL] full audit does NOT pass -- see /tmp/audit_out.txt"
  cat /tmp/audit_out.txt
  ((FAIL++))
fi
build_submission_bundle >/tmp/bundle_out.txt 2>&1
BUNDLE=$(grep -oE '/[^ ]+\.tar\.gz' /tmp/bundle_out.txt | head -1)
check "submission bundle file exists" '[[ -n "$BUNDLE" && -f "$BUNDLE" ]]'
if [[ -n "$BUNDLE" ]]; then
  MEMBERS=$(tar -tzf "$BUNDLE" 2>/dev/null)
  check "bundle contains audit-result.txt" '[[ "$MEMBERS" == *audit-result.txt* ]]'
  check "bundle contains session-summary.txt" '[[ "$MEMBERS" == *session-summary.txt* ]]'
  check "bundle contains sandbox-snapshot" '[[ "$MEMBERS" == *sandbox-snapshot* ]]'
fi

echo
echo "== Progress persistence + slugify =="
NAME="Thabo M."
PROGRESS_FILE="$(progress_path_for "$NAME")"
STAGE=2; STEP=14; SCORE=340; STREAK=3; BEST_STREAK=6; HINTS_USED=2
LEARNED_POOL=(pwd ls cd mkdir)
save_progress
check "progress file created with expected slug" '[[ -f "$REAL_HOME/.iklwa-trainer-progress-thabo-m" ]]'
STAGE=0; STEP=0; SCORE=0
load_progress
check "reload restores stage" '[[ "$STAGE" == "2" ]]'
check "reload restores step" '[[ "$STEP" == "14" ]]'
check "reload restores score" '[[ "$SCORE" == "340" ]]'
check "reload restores learned pool" '[[ "${#LEARNED_POOL[@]}" == "4" ]]'

echo
echo "== Reset behavior =="
NAME="Reset Case"
PROGRESS_FILE="$(progress_path_for "$NAME")"
STAGE=2; STEP=5
save_progress
check "reset-target progress file actually exists before reset" '[[ -f "$(progress_path_for "Reset Case")" ]]'
RESET_MODE="progress"
handle_reset >/dev/null
check "progress-only reset removes progress file" '[[ ! -f "$(progress_path_for "Reset Case")" ]]'
check "progress-only reset leaves sandbox intact" '[[ -d "$SANDBOX/cases/acme-corp" ]]'

echo
echo "=================================="
echo "PASS: $PASS   FAIL: $FAIL"
[[ $FAIL -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $(( FAIL > 0 ? 1 : 0 ))
