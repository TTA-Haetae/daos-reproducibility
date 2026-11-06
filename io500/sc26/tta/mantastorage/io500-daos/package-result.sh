#!/bin/bash
#
# Package a result the way run-io500.sh's create_tarball() does, for runs
# that ended with the known DFS_Finalize abort: the launcher stops before
# create_tarball, so the rendered ini and the launcher are not copied into
# the result dir and no tarball is made. On Haetae-01:
#   package-result.sh <result_ts> <rendered ini name> <launcher log> <launcher exit status>
#   package-result.sh 2026.11.03-10.12.00 config-research.ini /tmp/io500-x-r1-101200.log 5
# It packages nothing unless, on its own inputs:
#   - lib.sh run_end on the whole launcher log with that exit status, the
#     ini's stonewall-time and enabled phases says "FINALIZE_ABORT <result_ts>"
#   - every phase enabled in the ini has a score > 0 in result.txt and
#     there is a [SCORE] section (lib.sh check_scores; result_summary.txt is
#     empty after the known abort and is left as io500 wrote it)
#   - the rendered ini is byte-identical to io500's config-orig.ini copy
#   - no tarball for the timestamp exists yet
# Then the same steps as create_tarball(): copy the launcher and the
# rendered ini into the result dir, then tar it as
# results/io500-<host>-<ts>.tgz. The launcher log, its exit status, the
# run_end verdict and the md5 of the launcher go into the result dir too
# (launcher.log, launcher.rc, packaged-by.txt), so the tarball carries the
# evidence for why it was packaged by hand.

set -euo pipefail
. "$(dirname "$0")/lib.sh"

[ $# -eq 4 ] || { echo "usage: $0 <result_ts> <ini> <launcher log> <exit status>" >&2; exit 1; }
TS="$1"
INI="$2"
LOG="$3"
RC="$4"
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
IO500_DIR="${IO500_DIR:-$HOME/io500-clean}"

[[ "$TS" =~ $TS_RE ]] || { echo "bad timestamp $TS" >&2; exit 1; }
[[ "$INI" =~ ^[A-Za-z0-9._-]+\.ini$ ]] || { echo "bad ini name $INI" >&2; exit 1; }
[[ "$RC" =~ ^[0-9]+$ ]] || { echo "bad exit status $RC" >&2; exit 1; }
LOG="$(cd "$(dirname "$LOG")" && pwd)/$(basename "$LOG")"
[ -s "$LOG" ] || { echo "no launcher log $LOG" >&2; exit 1; }
cd "$IO500_DIR"
dir="results/$TS"
tarball="results/io500-$HOSTNAME-$TS.tgz"
[ -s "$dir/result.txt" ] || { echo "no $dir/result.txt" >&2; exit 1; }
[ -e "$tarball" ] && { echo "$tarball exists, not overwritten" >&2; exit 1; }
# The rendered ini in the io500 dir is overwritten by the next run with the
# same template; io500's own config-orig.ini is a byte copy of the ini it
# was started with, so the two must be identical
cmp -s "$INI" "$dir/config-orig.ini" ||
  { echo "$INI differs from $dir/config-orig.ini; not the ini of this run" >&2; exit 1; }

sw=$(awk -F' *= *' '$1 == "stonewall-time" { print $2 }' "$INI")
[[ "$sw" =~ ^[0-9]+$ ]] || { echo "no stonewall-time in $INI" >&2; exit 1; }
mapfile -t phases < <(enabled_phases < "$INI")
end=$(tr -d '\000' < "$LOG" > "$dir/launcher.log" && run_end "$dir/launcher.log" "$RC" "$sw" "${phases[@]}")
if [ "$end" != "FINALIZE_ABORT $TS" ]
then
  rm -f "$dir/launcher.log"
  echo "run_end says '$end', not 'FINALIZE_ABORT $TS': not the known abort, not packaged" >&2
  exit 1
fi
scores=$(check_scores "$dir/result.txt" "${phases[@]}") ||
  { rm -f "$dir/launcher.log"; echo "$scores" >&2; echo "missing or zero score, not packaged" >&2; exit 1; }

echo "$RC" > "$dir/launcher.rc"
cp -v "$KIT_DIR/run-io500.sh" "$INI" "$dir/"
{
  echo "packaged by $(basename "$0") on $(date -Is)"
  echo "run_end: $end (exit $RC, stonewall $sw): the launcher ended with the known"
  echo "  DFS_Finalize MPI_Barrier / MPI_ERR_COMM abort after the results were written"
  echo "launcher log: launcher.log, exit status: launcher.rc"
  md5sum "$KIT_DIR/run-io500.sh" "$KIT_DIR/lib.sh" "$KIT_DIR/package-result.sh" | sed 's/^/md5 /'
} > "$dir/packaged-by.txt"
tar czf "$tarball" -C results "$TS"
echo "Created result tarball ./$tarball"
