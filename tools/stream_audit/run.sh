#!/usr/bin/env bash
# NET-08's stream audit, as CI runs it. Exits non-zero on any violation.
#   tools/stream_audit/run.sh push          60 s of four bots, audited in the scenario kit (every push)
#   tools/stream_audit/run.sh nightly       30 minutes of the same (FND-04's nightly slot)
#   tools/stream_audit/run.sh <dir>         the *.audit.json reports dev or QA servers wrote there
#                                           (--stream-audit <path>)
# A failure prints the tick, the client, the record, the rule and the soak's seed to reproduce it.
set -euo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$GAME_DIR"
what="${1:-push}"
case "$what" in
	push|nightly)
		start=$(date +%s)
		out="build/soaks/stream_audit_$what"
		status=0
		./tools/bots/run_soak.sh "stream_audit_$what" --accelerated --out "$out" || status=$?
		echo "stream audit ($what): $(( $(date +%s) - start )) s; report $out/report.json"
		exit $status
		;;
	*)
		[ -d "$what" ] || { echo "stream_audit: no directory $what" >&2; exit 2; }
		shopt -s nullglob
		reports=("$what"/*.audit.json)
		[ ${#reports[@]} -gt 0 ] || { echo "stream_audit: no *.audit.json in $what" >&2; exit 1; }
		bad=0
		for r in "${reports[@]}"; do
			n=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["violations"])' "$r")
			if [ "$n" != "0" ]; then
				echo "FAIL $r: $n violations" >&2
				python3 -c 'import json,sys; [print("  ", v) for v in json.load(open(sys.argv[1]))["first"][:20]]' "$r" >&2
				bad=1
			else
				echo "ok   $r: no violations"
			fi
		done
		exit $bad
		;;
esac
