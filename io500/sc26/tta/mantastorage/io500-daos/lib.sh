#!/bin/bash
#
# Parsers and checks shared by the scripts in this directory. Each parser
# reads the JSON (-j) output of a daos/dmg command, or an io500 result file,
# on stdin. Every parser fails
# closed: empty input, non-JSON, status != 0, a missing field or an
# unexpected type is an error. A well-formed empty list is not an error.

# Fixed names of the two tracks' containers; nothing else is ever destroyed
OWN_CONT_RE='^(io500-(prod|research)|haetae-(production|research))$'
# Values passed to remote shells: labels, file names, K=V pairs
SAFE_RE='^[A-Za-z0-9._:/=-]+$'
# Pool labels, and pool sizes as dmg accepts them (100%, 200TB, 1.5TiB)
POOL_RE='^[A-Za-z0-9_.-]+$'
SIZE_RE='^([0-9]+%|[0-9]+(\.[0-9]+)?[KMGTP]i?B)$'
# io500 result timestamps
TS_RE='^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]{2}\.[0-9]{2}\.[0-9]{2}$'

# safe_word <value>...: every value matches SAFE_RE
safe_word() {
  local w
  for w in "$@"
  do
    [[ "$w" =~ $SAFE_RE ]] || { echo "unsafe value: '$w'" >&2; return 1; }
  done
}

safe_pool() { [[ "$1" =~ $POOL_RE ]] || { echo "bad pool label: '$1'" >&2; return 1; }; }
safe_size() { [[ "$1" =~ $SIZE_RE ]] || { echo "bad pool size: '$1'" >&2; return 1; }; }

# jqin <jq args>...: jq on stdin, but empty input is an error (jq itself
# exits 0 on empty input). error() in a filter exits 5, a parse error 2.
jqin() {
  local in
  in=$(cat)
  [ -n "$in" ] || { echo "empty input" >&2; return 1; }
  jq "$@" <<< "$in"
}

# daos container list -j: one label per line (none for an empty pool)
cont_labels() {
  jqin -r 'if .status == 0 and (.response | type == "array")
           then .response[].label else error("daos cont list failed") end'
}

# dmg pool list -j: one pool label per line (none if there is no pool; dmg
# 2.8 prints "pools": null then, a missing key is still an error)
pool_labels() {
  jqin -r 'if .status == 0 and (.response | has("pools"))
              and (.response.pools | type == "array" or type == "null")
           then (.response.pools // [])[].label else error("dmg pool list failed") end'
}

# daos container get-prop -j, checked against a profile:
#   prod      rd_fac "1", rd_lvl "node"
#   research  rd_fac "0"
# Prints "rd_fac=<v> rd_lvl=<v> ec_cell_sz=<v>".
check_cont_props() {
  local profile="$1"
  jqin -r --arg p "$profile" '
    if .status != 0 or (.response | type != "array") then error("get-prop failed") else . end
    | (.response | map({(.name): (.value | tostring)}) | add) as $v
    | if   $p == "prod"     then ($v.rd_fac == "1" and $v.rd_lvl == "node")
      elif $p == "research" then ($v.rd_fac == "0")
      else error("unknown profile") end
    | if . then "rd_fac=\($v.rd_fac) rd_lvl=\($v.rd_lvl) ec_cell_sz=\($v.ec_cell_sz)"
      else error("rd_fac=\($v.rd_fac) rd_lvl=\($v.rd_lvl) does not match \($p)") end'
}

# dmg pool query -j: Ready, no disabled target, rebuild idle/done with
# status 0 and degraded exactly false. Prints a one-line summary.
pool_health() {
  jqin -r '
    if .status != 0 then error("pool query failed") else .response end
    | . as $r
    | ($r.state == "Ready" and ($r.disabled_targets | type == "number") and $r.disabled_targets == 0
       and $r.rebuild.status == 0 and ($r.rebuild.state | IN("idle", "done"))
       and $r.rebuild.degraded == false) as $ok
    | "state=\($r.state) disabled=\($r.disabled_targets)/\($r.total_targets) rebuild=\($r.rebuild.state)/\($r.rebuild.status) degraded=\($r.rebuild.degraded)"
    | if $ok then . else error("pool unhealthy: " + .) end'
}

# dmg pool query -j: free bytes per tier and the smallest per-target free
# space: "uuid=<u> scm_free=<b> scm_min=<b> nvme_free=<b> nvme_min=<b>"
pool_space() {
  jqin -r '
    if .status != 0 then error("pool query failed") else .response end
    | (.tier_stats | map({(.media_type): .}) | add) as $t
    | if ($t.scm.free | type) != "number" or ($t.nvme.free | type) != "number"
         or ($t.scm.min | type) != "number" or ($t.nvme.min | type) != "number"
      then error("tier_stats missing") else . end
    | "uuid=\(.uuid) scm_free=\($t.scm.free) scm_min=\($t.scm.min) nvme_free=\($t.nvme.free) nvme_min=\($t.nvme.min)"'
}

# dmg pool get-prop -j: the properties that change placement, recovery or
# capacity, one "name=value" line each, sorted. Part of the run snapshot,
# because they can change without any restart.
POOL_PROP_NAMES='"data_thresh", "rd_fac", "self_heal", "space_rb", "svc_rf", "svc_list", "ec_cell_sz", "checkpoint", "checkpoint_freq", "checkpoint_thresh", "reclaim", "label"'
pool_props() {
  local out
  # Not piped straight into sort: a jq error must be this function's status.
  # Every listed name must appear exactly once.
  out=$(jqin -r "
    if .status != 0 or (.response | type != \"array\") then error(\"pool get-prop failed\") else . end
    | [.response[] | select(.name | IN($POOL_PROP_NAMES))] as \$sel
    | [$POOL_PROP_NAMES] as \$want
    | [\$want[] as \$n | {n: \$n, c: ([\$sel[] | select(.name == \$n)] | length)} | select(.c != 1)] as \$bad
    | if (\$bad | length) > 0 then error(\"pool properties not exactly once: \" + (\$bad | tojson)) else . end
    | \$sel[] | \"\\(.name)=\\(.value | tojson)\"") || return 1
  sort <<< "$out"
}

# pool_props output on stdin, expected data_thresh in bytes: exactly one
# data_thresh line with that value
check_data_thresh() {
  local want="$1" got
  got=$(grep '^data_thresh=' | sed 's/^data_thresh=//')
  [ "$got" = "$want" ] || { echo "data_thresh is '${got:-missing}', expected $want" >&2; return 1; }
}

# dmg system query -j: "rank=<r> state=<s> inc=<incarnation>" per engine,
# sorted. A restarted engine gets a new incarnation. rank and incarnation
# must be numbers, state a string, and no rank may appear twice.
engine_state() {
  jqin -r 'if .status != 0 or (.response.members | type != "array")
           then error("system query failed") else . end
           | .response.members
           | if all(.[]; (.rank | type) == "number" and (.incarnation | type) == "number"
                         and (.state | type) == "string")
             then . else error("member without numeric rank/incarnation or state") end
           | if (map(.rank) | unique | length) == length then . else error("duplicate rank") end
           | sort_by(.rank)[]
           | "rank=\(.rank) state=\(.state) inc=\(.incarnation)"'
}

# engine_state output on stdin: exactly <n> lines, all of the full form,
# ranks 0..n-1 once each, all joined
engines_joined() {
  local n="$1" in
  in=$(cat)
  [ -n "$in" ] || return 1
  awk -v n="$n" '
    !/^rank=[0-9]+ state=[a-z]+ inc=[0-9]+$/ { bad = 1; next }
    { split($1, r, "="); seen[r[2]]++; c++; if ($2 != "state=joined") bad = 1 }
    END { if (bad || c != n) exit 1; for (i = 0; i < n; i++) if (seen[i] != 1) exit 1 }' <<< "$in"
}

# rendered ini on stdin: phases with run = TRUE that print a score line
# (the parameter sections ior-easy, ior-hard, mdtest-easy, mdtest-hard and
# find-easy do not)
enabled_phases() {
  awk '/^\[.*\]$/ { s = substr($0, 2, length($0) - 2) }
       /^run = TRUE/ { print s }' |
    grep -v -x -E 'ior-easy|ior-hard|mdtest-easy|mdtest-hard|find-easy' || true
}

# Scores come from io500's result.txt, not result_summary.txt: with the
# official build the known DFS_Finalize abort (lib.sh run_end) hits during
# phase cleanup, before io500 closes result_summary.txt, so that file is
# always empty, while result.txt is flushed after every phase.
#
# score_of <phase> <result.txt>: the "score = <v>" value of the [<phase>]
# section; prints nothing unless there is exactly one such section with
# exactly one numeric score line
score_of() {
  awk -v p="[$1]" '
    /^\[.*\]$/ { in_sec = ($0 == p); if (in_sec) secs++; next }
    in_sec && $1 == "score" && $2 == "=" { n++; v = $3 }
    END { if (secs == 1 && n == 1 && v ~ /^[0-9]+(\.[0-9]+)?$/) print v }' "$2"
}

# check_scores <result.txt> <phase>...: every phase has a score > 0 and the
# file has one [SCORE] section with numeric MD, BW and SCORE; prints one
# "<phase>=<v>" line per phase and a "[SCORE] MD=.. BW=.. SCORE=.." line
check_scores() {
  local result="$1" p v bad=0
  shift
  [ $# -gt 0 ] || { echo "no enabled phase" >&2; return 1; }
  [ -s "$result" ] || { echo "missing $result" >&2; return 1; }
  for p in "$@"
  do
    v=$(score_of "$p" "$result")
    echo "$p=${v:-missing}"
    awk -v v="${v:-0}" 'BEGIN { exit !(v + 0 > 0) }' || bad=1
  done
  awk '
    /^\[.*\]$/ { in_sec = ($0 == "[SCORE]"); if (in_sec) secs++; next }
    in_sec && $2 == "=" && ($1 == "MD" || $1 == "BW" || $1 == "SCORE") {
      if ($3 !~ /^[0-9]+(\.[0-9]+)?$/) bad = 1
      if (seen[$1]++) bad = 1
      out = out " " $1 "=" $3 ($4 == "" ? "" : " " $4)
    }
    END {
      if (secs != 1 || bad || !seen["MD"] || !seen["BW"] || !seen["SCORE"]) exit 1
      print "[SCORE]" out
    }' "$result" || { echo "no valid [SCORE] section" >&2; bad=1; }
  return $bad
}

# ior-easy-write.txt on stdin: "pairs_min=<a> pairs_max=<b> ratio=<a/b>"
easyw_balance() {
  awk '/stonewalling pairs accessed min:/ {
         for (i = 1; i <= NF; i++) { if ($i == "min:") a = $(i + 1); if ($i == "max:") b = $(i + 1) }
       }
       END { if (b + 0 <= 0) exit 1; printf "pairs_min=%d pairs_max=%d ratio=%.3f\n", a, b, a / b }'
}

# find_balance <find.csv>: how evenly pfind's ranks shared the find phase.
# pfind reads each directory split (dfs_obj_anchor_split) on one rank and a
# steal request hands over one item, so the mdtest-hard directory (all files
# in one dir) gives a few huge items; when one rank ends up with two, every
# other rank waits in work stealing and find takes ~2x. Prints
#   find_max=<checked> find_p99=<checked> find_ratio=<max/p99>
#   find_steal_mean=<s> find_straggler=yes|no find_runtime=<s>
#   find_steal_ratio=<steal mean / runtime>
# (one line), straggler when max/p99 >= 1.5 (normal runs: 1.01-1.02).
# find_steal_ratio is the share of the find phase an average rank spent
# waiting in work stealing: Research ~0.15, Production ~0.7 even without a
# straggler (e.g. 52.7 s of 71.3 s), i.e. few, large directory splits.
# find_runtime is pfind's own "runtime:" (first line); n/a if that is missing.
find_balance() {
  local f="$1" rows
  [ -s "$f" ] || { echo "missing $f" >&2; return 1; }
  # rows: "rank, errors, unknown, found, total, checked, ..., <time>s, tokens"
  rows=$(sed -n '3,$p' "$f" | awk -F', *' '
    {
      t = $11; sub(/s$/, "", t)
      ok = (NF == 12 && t ~ /^[0-9]+(\.[0-9]+)?$/)
      for (k = 1; k <= 12; k++) if (k != 11 && $k !~ /^[0-9]+$/) ok = 0
      if (!ok) exit 1
      print $6, t
    }') || { echo "bad find.csv $f" >&2; return 1; }
  [ "$(grep -c . <<< "$rows")" -ge 2 ] || { echo "bad find.csv $f: no rank rows" >&2; return 1; }
  local rt
  rt=$(sed -n '1s/^runtime: *\([0-9][0-9.]*\) .*/\1/p' "$f")
  sort -n <<< "$rows" | awk -v rt="$rt" '
    { c[NR] = $1; st += $2 }
    END {
      i = int(NR * 0.99); if (i < 1) i = 1
      r = c[NR] / (c[i] > 0 ? c[i] : 1)
      printf "find_max=%d find_p99=%d find_ratio=%.2f find_steal_mean=%.1fs find_straggler=%s",
        c[NR], c[i], r, st / NR, (r >= 1.5 ? "yes" : "no")
      if (rt + 0 > 0)
        printf " find_runtime=%.1fs find_steal_ratio=%.2f\n", rt, st / NR / rt
      else
        printf " find_runtime=n/a find_steal_ratio=n/a\n"
    }'
}

# Exit status of the launcher when MPI_ERRORS_ARE_FATAL aborts the job on
# MPI_ERR_COMM (error class 5), as observed with the unmodified build
KNOWN_ABORT_RC=5

# The io500 messages a smoke run (stonewall < 300) prints for its own
# shortness; nothing else marked ERROR is ever accepted
SMOKE_INVALID_RE='^ERROR INVALID \(src/phase_dbg\.c:[0-9]+\) stonewall-time [0-9]+s != 300s$|^ERROR INVALID \(src/main\.c:[0-9]+\) Runtime is smaller than expected minimum runtime$'
# The two messages io500 prints before the [RESULT] line of a phase that the
# ini disabled (score 0, runtime 0) in a partial (screening) run
OFF_PHASE_RE='^ERROR INVALID \(src/main\.c:[0-9]+\) (Runtime of phase \([0-9.eE+-]+\) is below stonewall time\. This shouldn.t happen!|Resulting score shouldn.t be 0\.0)$'

# run_end <launcher log> <launcher exit status> <stonewall> [<enabled phase>...]: how
# run-io500.sh ended. Prints "<state> <result_ts>" (result_ts empty if the
# log has no single result dir line).
#   COMPLETE        exit 0, one result dir line, [SCORE] line,
#                   "Created result tarball" for that timestamp, no MPI
#                   error block, no other error line
#   FINALIZE_ABORT  the known upstream IOR bug with the unmodified build:
#                   IOR's DFS_Finalize calls MPI_Barrier on the testComm
#                   that test_finalize() already freed, and MPI aborts the
#                   job after io500 printed the results, before
#                   create_tarball. Accepted only with exit KNOWN_ABORT_RC,
#                   one result dir line, a [SCORE] line, no tarball line,
#                   at least one Open MPI error block, every block exactly
#                   that signature (below), and no other error line.
#   FAILED          anything else
# The whole log is checked, not only what follows the result dir line:
# ranks are not synchronized after the results, so a rank may abort before
# rank 0 prints them, and 1440 ranks may each print the block. Open MPI
# block lines are "[host:pid] *** <text>"; one rank's block is these six
# texts, so for every host:pid prefix each of the six must occur equally
# often (several ranks may share a prefix), and any other text is fatal.
# When many ranks print the block, Open MPI's help aggregation adds lines
# "<n> more process(es) has/have sent help message help-mpi-errors.txt
# / mpi_errors_are_fatal" (the file name sometimes carries a timestamp);
# exactly those are accepted, and only if at least one block was seen
# (e.g. six such lines after a valid FINALIZE_ABORT).
# Outside the blocks any ERROR/FATAL/abort/signal/kill/fail marker is fatal,
# except the SMOKE_INVALID_RE lines when stonewall < 300; at stonewall
# >= 300 an [INVALID] tag is fatal too.
# Partial (screening) runs: with stonewall < 300 and the enabled phases given
# as the 4th argument, an OFF_PHASE_RE line is accepted only if the next
# [RESULT] / [      ] line is a phase not in that list with value 0;
# otherwise (an enabled phase, a non-zero value, no such line, or no list)
# it is fatal.
# When ior-easy-write / ior-hard-write is not among the given phases
# (stonewall < 300), io500 still runs that phase's cleanup after the results
# and DFS prints, for the files it never created, "ERROR (aiori-DFS.c:<n>):
# <rank>: 2: Failed to remove path //<ts>/ior-easy/ior_file_easy.<rank>"
# (2 = ENOENT) and "Failed to lookup parent: //<ts>/ior-easy", or
# "... Failed to remove path //<ts>/ior-hard/file"; exactly these lines, for
# this run's timestamp and only for the disabled phase, are accepted then.
RUN_END_AWK='
  function cls(b) {
    if (b == "An error occurred in MPI_Barrier") return 1
    if (b ~ /^reported by process \[[0-9]+,[0-9]+\]$/) return 2
    if (b == "on communicator MPI_COMM_WORLD") return 3
    if (b == "MPI_ERR_COMM: invalid communicator") return 4
    if (b == "MPI_ERRORS_ARE_FATAL (processes in this communicator will now abort,") return 5
    if (b ~ /^ *and MPI will try to terminate your MPI job as well\)$/) return 6
    return 0
  }
  /^\[[^]]+\] \*\*\* / {
    i = index($0, "] *** "); pre = substr($0, 2, i - 2); body = substr($0, i + 6)
    k = cls(body)
    if (k == 0) { bad++; next }
    cnt[pre, k]++; pres[pre] = 1; next
  }
  /^[0-9]+ more process(es)? (has|have) sent help message help-mpi-errors\.txt(-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9])? \/ mpi_errors_are_fatal$/ { agg++; next }
  sw < 300 && $0 ~ ENVIRON["SMOKE_INVALID_RE"] { next }
  sw < 300 && $0 ~ ENVIRON["OFF_PHASE_RE"] { pending++; next }
  ENVIRON["OFF_CLEANUP_RE"] != "" && $0 ~ ENVIRON["OFF_CLEANUP_RE"] { next }
  /^\[(RESULT|      )\] / {
    if (pending) {
      split(substr($0, 9), f, " ")
      if (en ~ /[^ ]/ && index(en, " " f[1] " ") == 0 && f[2] ~ /^0(\.0+)?$/) pending = 0
      else { other += pending; pending = 0 }
    }
  }
  /ERROR|FATAL|[Ee]rror|[Aa]bort|[Ss]egmentation|signal|core dumped|[Kk]illed|exited on|[Ff]ail/ { other++ }
  sw >= 300 && /\[INVALID\]/ { other++ }
  /^\[SCORE \] / { score++ }
  index($0, "Created result tarball ./results/io500-") == 1 &&
    substr($0, length($0) - length(tsuf) + 1) == tsuf { tarball++ }
  END {
    other += pending
    for (p in pres) {
      for (k = 2; k <= 6; k++) if (cnt[p, k] != cnt[p, 1]) bad++
      blocks += cnt[p, 1]
    }
    if (agg && !blocks) bad++
    printf "%d %d %d %d %d\n", blocks, bad, other, score, tarball
  }'

run_end() {
  local log="$1" rc="$2" sw="$3" en dirs ts blocks bad other score tarball
  shift 3
  en=" $* "
  if ! [[ "$rc" =~ ^[0-9]+$ ]] || ! [[ "$sw" =~ ^[0-9]+$ ]] || [ ! -s "$log" ]
  then
    echo "FAILED"; return
  fi
  dirs=$(grep -a -E '^The result files are stored in the directory: \./results/' "$log" | sed 's|.*/||')
  if [ "$(grep -c . <<< "$dirs")" != 1 ] || ! [[ "$dirs" =~ $TS_RE ]]
  then
    echo "FAILED"; return
  fi
  ts="$dirs"
  local off_cleanup="" tsre re
  if [ "$sw" -lt 300 ] && [ -n "${en// /}" ]
  then
    tsre="${ts//./\\.}"
    re="^ERROR \\(aiori-DFS\\.c:[0-9]+\\): [0-9]+: 2: Failed to remove path //$tsre"
    [[ "$en" == *" ior-easy-write "* ]] ||
      off_cleanup="$re/ior-easy/ior_file_easy\\.[0-9]+\$|^Failed to lookup parent: //$tsre/ior-easy\$"
    [[ "$en" == *" ior-hard-write "* ]] ||
      off_cleanup="${off_cleanup:+$off_cleanup|}$re/ior-hard/file\$"
  fi
  read -r blocks bad other score tarball < <(SMOKE_INVALID_RE="$SMOKE_INVALID_RE" OFF_PHASE_RE="$OFF_PHASE_RE" OFF_CLEANUP_RE="$off_cleanup" \
    LC_ALL=C awk -v sw="$sw" -v en="$en" -v tsuf="-$ts.tgz" "$RUN_END_AWK" "$log")
  if [ "$bad" = 0 ] && [ "$other" = 0 ] && [ "$score" = 1 ]
  then
    if [ "$rc" = 0 ] && [ "$tarball" = 1 ] && [ "$blocks" = 0 ]
    then
      echo "COMPLETE $ts"; return
    fi
    if [ "$rc" = "$KNOWN_ABORT_RC" ] && [ "$tarball" = 0 ] && [ "$blocks" -ge 1 ]
    then
      echo "FINALIZE_ABORT $ts"; return
    fi
  fi
  echo "FAILED $ts"
}

# invalid_reasons <result.txt>: the run was invalid only because it was a
# smoke run: every "; ERROR" line of result.txt is the stonewall-time or the
# minimum-runtime message, and the stonewall-time one is present
invalid_reasons() {
  local f="$1"
  [ -s "$f" ] || return 1
  grep -q -E '^; ERROR INVALID stonewall-time [0-9]+s != 300s$' "$f" || return 1
  ! grep -E '^; ERROR' "$f" |
    grep -q -v -E '^; ERROR INVALID (stonewall-time [0-9]+s != 300s|Runtime is smaller than expected minimum runtime)$'
}

# verify_state <verify.txt> <rc> <stonewall> <result.txt>: VALID, INVALID or ERROR
#   ERROR    any "ERROR" line, no "[OK]" line, or any other combination
#            below; io500 --verify prints "[OK] But this is an invalid run!"
#            even after a config hash mismatch, which it reports only as an
#            "ERROR: Configuration hash ..." line
#   INVALID  "[OK] But this is an invalid run!" with exit 1, a smoke
#            stonewall (< 300) and only smoke reasons in result.txt
#            (invalid_reasons); at stonewall 300 it is an ERROR
#   VALID    "[OK]" without the invalid note, exit 0
verify_state() {
  local f="$1" rc="$2" sw="$3" res="$4"
  if grep -q '^ERROR' "$f" || ! grep -q '^\[OK\]' "$f"
  then
    echo ERROR
  elif grep -q '^\[OK\] But this is an invalid run' "$f"
  then
    if [ "$rc" = 1 ] && [[ "$sw" =~ ^[0-9]+$ ]] && [ "$sw" -lt 300 ] && invalid_reasons "$res"
    then
      echo INVALID
    else
      echo ERROR
    fi
  elif [ "$rc" = 0 ]
  then
    echo VALID
  else
    echo ERROR
  fi
}

# Engine telemetry (Prometheus text from the exporter on :9191) on stdin.
# Values are floats with about 7 significant digits.

# gc_total <pool uuid> [<series>]: "<sum> <series>" of the VOS GC deletion
# counters (obj, dkey, akey, sv, ev, cont) of that pool over all ranks and
# targets the exporter serves. An error if the count of series is not
# <series> (default 192 = 2 ranks x 16 targets x 6 counters) or a value is
# not a number. The counters stop moving when GC has nothing left to do.
gc_total() {
  local pool="$1" want="${2:-192}"
  awk -v p="pool=\"$pool\"" -v want="$want" '
    /^engine_pool_vos_gc_(obj|dkey|akey|sv|ev|cont)_del\{/ && index($1, p) {
      if ($NF !~ /^[0-9.e+-]+$/) bad = 1
      s += $NF; n++
    }
    END { if (bad || n != want) exit 1; printf "%.0f %d\n", s, n }'
}

# space_check <pool uuid> <ranks> <targets>: checks the VOS space series of
# that pool: every one of <ranks> ranks reports scm/nvme used/total once for
# each target 0..<targets>-1 with a numeric value, and nothing else for the
# pool. Prints one "rank=<r> missing=<m> dup=<d> extra=<e> nonnum=<n>" line
# per rank with a problem, plus "ranks=<seen>/<ranks>" if ranks are missing,
# and exits 1 if anything was printed.
space_check() {
  awk -v p="pool=\"$1\"" -v want="$2" -v tgts="$3" '
    function label(s, k,   re) {
      re = k "=\"[^\"]*\""
      if (match(s, re)) return substr(s, RSTART + length(k) + 2, RLENGTH - length(k) - 3)
      return "-"
    }
    /^engine_pool_vos_space_(scm|nvme)_(used|total)\{/ && index($1, p) {
      name = $1; sub(/\{.*/, "", name)
      r = label($1, "rank"); t = label($1, "target")
      ranks[r] = 1
      if (t !~ /^[0-9]+$/ || t + 0 >= tgts) { extra[r]++; next }
      if ($NF !~ /^[0-9.e+-]+$/) nonnum[r]++
      c[r, t + 0, name]++
    }
    END {
      split("engine_pool_vos_space_scm_used engine_pool_vos_space_scm_total engine_pool_vos_space_nvme_used engine_pool_vos_space_nvme_total", m, " ")
      nr = 0
      for (r in ranks) {
        nr++; miss = 0; dup = 0
        for (t = 0; t < tgts; t++) for (i = 1; i <= 4; i++) {
          k = c[r, t, m[i]]
          if (k == 0) miss++; else if (k > 1) dup++
        }
        if (miss || dup || extra[r] || nonnum[r]) {
          printf "rank=%s missing=%d dup=%d extra=%d nonnum=%d\n", r, miss, dup, extra[r] + 0, nonnum[r] + 0; bad = 1
        }
      }
      if (nr != want) { printf "ranks=%d/%d\n", nr, want; bad = 1 }
      exit bad
    }'
}
