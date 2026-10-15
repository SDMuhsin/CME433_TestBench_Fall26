#!/usr/bin/env bash
# Digest of a Calibre DRC summary (stdout): total results, results per rule check
# (rule check names and counts only), density rules separated out.
sum=$1
echo "calibre drc digest of $(basename "$sum")"
awk '/RULECHECK .* TOTAL Result Count = [1-9]/ {print $2, $NF}' "$sum" | sort -u > rules.tmp
tot=$(awk '{s+=$2} END {print s+0}' rules.tmp)
den=$(grep -iE 'DN|DENSITY' rules.tmp | awk '{s+=$2} END {print s+0}')
echo "total $tot results in $(wc -l < rules.tmp) rule checks (density rules: $den)"
echo "rule checks with results:"
sed 's/^/  /' rules.tmp
grep -E 'TOTAL (DRC|RuleChecks|Original Layer|Result)' "$sum" | sed 's/^/  /' | head -8
mv rules.tmp rules.txt
