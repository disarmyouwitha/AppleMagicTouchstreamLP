#!/bin/zsh
set -u
probe_validation_dir="${0:A:h}"
cd "$probe_validation_dir/.." || exit 2
mkdir -p "$probe_validation_dir/captures" "$probe_validation_dir/reports"
swift run RewriteProbe --plan "$probe_validation_dir/session.json" --output "$probe_validation_dir/reports"
probe_exit=$?
if [[ "$probe_exit" == 3 ]]; then
  print "\nSome captures or required fields are still missing. This is expected before recording."
elif [[ "$probe_exit" == 1 ]]; then
  print "\nSome observations differ from the declared trial. Keep the captures; we will inspect them together."
fi
print "\nReport: $probe_validation_dir/reports/report.md"
print "Press Return to close."
read -r
exit "$probe_exit"
