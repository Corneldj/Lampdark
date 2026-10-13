#!/usr/bin/env bash
# NET-12's nightly entry (FND-04's slot): the criterion-4 report at 40, 120, 200 and 250 ms round
# trips with 2% loss, each for --minutes (default 30), into build/probes/rtt<rtt>_loss2/.
# Exits non-zero when the 120 ms run fails criterion 4 (the others, Q11's 200 ms included, are
# reported, not gated).
set -uo pipefail
GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MINUTES="${1:-30}"
status=0
for rtt in 40 120 200 250; do
	"$GAME_DIR/tools/bots/probe_report.sh" --rtt "$rtt" --loss 0.02 --minutes "$MINUTES" > /dev/null
	code=$?
	echo "rtt $rtt ms: $([ $code -eq 0 ] && echo pass || echo fail) (build/probes/rtt${rtt}_loss2/report.md)"
	if [ "$rtt" = "120" ] && [ $code -ne 0 ]; then
		status=1
	fi
done
exit "$status"
