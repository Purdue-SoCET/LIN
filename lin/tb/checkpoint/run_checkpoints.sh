#!/usr/bin/env bash
# =============================================================================
# LIN checkpoint runner. DO NOT EDIT -- protected by MANIFEST.sha256.
#
# usage:  lin/tb/checkpoint/run_checkpoints.sh            (from anywhere)
#         LIN_SRC=/path/to/lin/src lin/tb/checkpoint/run_checkpoints.sh
#
# Exit codes:
#   0  every checkpoint passes
#   1  at least one checkpoint fails (fix the RTL in lin/src and run again)
#   2  the harness itself is broken or was modified (STOP and report; do not fix RTL)
# Raw output is kept in lin/tb/checkpoint/out/{lint.log,build.log,sim.log,report.txt}.
# =============================================================================
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${LIN_SRC:-$(cd "$HERE/../../src" 2>/dev/null && pwd)}
OUT=$HERE/out
mkdir -p "$OUT"
REPORT=$OUT/report.txt
: > "$REPORT"
say() { echo "$*" | tee -a "$REPORT"; }

say "LIN checkpoint run $(date -Iseconds)"
say "RTL source: $SRC"
say "Verilator: $(verilator --version 2>/dev/null || echo 'NOT FOUND')"

# ---------------------------------------------------------------- integrity
if ! (cd "$HERE" && sha256sum --quiet -c MANIFEST.sha256 >> "$REPORT" 2>&1); then
    say "HARNESS INTEGRITY FAIL: checkpoint files differ from MANIFEST.sha256. Restore them; do not edit the harness."
    exit 2
fi
if [ -z "$SRC" ] || ! ls "$SRC"/*.sv > /dev/null 2>&1; then
    say "HARNESS ERROR: no .sv files found in RTL source directory '$SRC'"
    exit 2
fi
FILES=$(ls "$SRC"/*.sv)

# ---------------------------------------------------------------- CP0: structure and lint
declare -A RES
cp0_fail=0
c0() { say "CHECK CP0.$1 $2 $3"; [ "$2" = PASS ] || cp0_fail=1; }

if grep -lE '^\s*interface\s+bus_protocol_if' $FILES > /dev/null 2>&1; then
    c0 01 FAIL "lin/src defines bus_protocol_if ($(grep -lE '^\s*interface\s+bus_protocol_if' $FILES | xargs -n1 basename | tr '\n' ' ')); the interface comes from the AFTx07 repo / tb stub"
else
    c0 01 PASS "lin/src does not define bus_protocol_if"
fi

bad=""
for f in $FILES; do
    off=$(grep -c 'lint_off' "$f"); on=$(grep -c 'lint_on' "$f")
    [ "$off" -eq "$on" ] || bad="$bad $(basename "$f")(off=$off,on=$on)"
done
if [ -z "$bad" ]; then c0 02 PASS "every lint_off has a matching lint_on (no file-wide waivers)"
else c0 02 FAIL "unpaired lint_off pragmas:$bad"; fi

if grep -qE '^\s*interface\s+lin_if' $FILES && grep -hA12 -E '^\s*interface\s+lin_if' $FILES | grep -q 'irq' \
   && grep -hA12 -E '^\s*interface\s+lin_if' $FILES | grep -q 'modport\s\+peripheral' \
   && grep -hA12 -E '^\s*interface\s+lin_if' $FILES | grep -q 'modport\s\+soc'; then
    c0 03 PASS "lin_if defines irq and modports peripheral and soc (spec 6.1)"
else
    c0 03 FAIL "lin_if must contain tx, tx_en, rx, irq and modports peripheral and soc (spec 6.1)"
fi

verilator --lint-only -Wall --top-module lin_lint_top \
    "$HERE/bus_protocol_if.sv" $FILES "$HERE/lin_lint_top.sv" > "$OUT/lint.log" 2>&1
lint_rc=$?
nwarn=$(grep -c '^%Warning' "$OUT/lint.log")
nerr=$(grep '^%Error' "$OUT/lint.log" | grep -vc 'Exiting due to')
if [ "$nerr" -eq 0 ] && [ "$nwarn" -eq 0 ] && [ "$lint_rc" -eq 0 ]; then
    c0 04 PASS "verilator --lint-only -Wall: 0 warnings, 0 errors"
else
    c0 04 FAIL "verilator --lint-only -Wall: $nwarn warnings, $nerr errors (see out/lint.log)"
    grep -E '^%(Warning|Error)' "$OUT/lint.log" | head -20 | sed 's/^/    /' | tee -a "$REPORT"
fi

rm -rf "$OUT/obj"
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --Mdir "$OUT/obj" --top-module tb_checkpoint \
    "$HERE/bus_protocol_if.sv" $FILES "$HERE/tb_checkpoint.sv" -j 4 > "$OUT/build.log" 2>&1
build_rc=$?
if [ "$build_rc" -eq 0 ] && [ -x "$OUT/obj/Vtb_checkpoint" ]; then
    c0 05 PASS "checkpoint testbench builds against lin/src"
else
    c0 05 FAIL "checkpoint testbench does not build (see out/build.log)"
    grep -E '^%Error' -A3 "$OUT/build.log" | head -20 | sed 's/^/    /' | tee -a "$REPORT"
fi
[ $cp0_fail -eq 0 ] && RES[CP0]=PASS || RES[CP0]=FAIL

# ---------------------------------------------------------------- CP1..CP4: simulation
declare -A EXPECT=( [CPT]=3 [CP1]=21 [CP2]=9 [CP3]=14 [CP4]=14 )
if [ "$build_rc" -eq 0 ] && [ -x "$OUT/obj/Vtb_checkpoint" ]; then
    ( cd "$OUT" && timeout 900 ./obj/Vtb_checkpoint ) > "$OUT/sim.log" 2>&1
    grep '^CHECK ' "$OUT/sim.log" | tee -a "$REPORT"
    grep -q '^TB_DONE' "$OUT/sim.log" || say "SIM DID NOT FINISH (crash, hang or timeout; see out/sim.log)"
    for cp in CPT CP1 CP2 CP3 CP4; do
        npass=$(grep -c "^CHECK $cp\.[0-9]* PASS" "$OUT/sim.log")
        nall=$(grep -c "^CHECK $cp\.[0-9]* " "$OUT/sim.log")
        if [ "$npass" -eq "${EXPECT[$cp]}" ] && [ "$nall" -eq "${EXPECT[$cp]}" ]; then RES[$cp]=PASS
        else RES[$cp]="FAIL ($npass/${EXPECT[$cp]})"; fi
    done
else
    for cp in CPT CP1 CP2 CP3 CP4; do RES[$cp]="FAIL (not built)"; done
fi

# ---------------------------------------------------------------- summary
say ""
say "================ CHECKPOINT SUMMARY ================"
say "CPT  harness self-test           : ${RES[CPT]}"
say "CP0  structure, lint, build      : ${RES[CP0]}"
say "CP1  reset values and registers  : ${RES[CP1]}"
say "CP2  master publish, bit-exact   : ${RES[CP2]}"
say "CP3  two nodes and timeouts      : ${RES[CP3]}"
say "CP4  error flags and control     : ${RES[CP4]}"
reached="none"
for cp in CP0 CP1 CP2 CP3 CP4; do
    [ "${RES[$cp]}" = PASS ] && reached=$cp || break
done
say "PROGRESS: highest checkpoint passed in order = $reached"
if [[ "${RES[CPT]}" == FAIL* ]] && [ "$build_rc" -eq 0 ]; then
    say "RESULT: HARNESS SELF-TEST FAILED -- STOP and report; this is not an RTL problem."
    exit 2
fi
for cp in CP0 CP1 CP2 CP3 CP4; do
    if [ "${RES[$cp]}" != PASS ]; then say "RESULT: FAIL"; exit 1; fi
done
say "RESULT: ALL CHECKPOINTS PASS"
exit 0
