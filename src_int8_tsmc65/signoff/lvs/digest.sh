#!/usr/bin/env bash
# Digest of a Calibre LVS report (stdout): overall result, cell verdict counts, top-cell
# port / net / instance counts, discrepancy and warning counts (no cell names).
rep=$1
echo "calibre lvs digest of $(basename "$rep")"
grep -m1 -oE 'NOT COMPARED|INCORRECT|CORRECT' "$rep" | sed 's/^/result: /'
grep -E '^ +(CORRECT|INCORRECT|NOT COMPARED) +[^ ]+ +[^ ]+ *$' "$rep" | awk '{print $1}' | sort | uniq -c |
    sed 's/^ */cells: /'
top=$(sed -n '/CELL COMPARISON RESULTS ( TOP LEVEL )/,$p' "$rep")
echo "top cell (initial, after transformation):"
grep -E '^ (Ports|Nets):|^ Total Inst:' <<< "$top" | sed 's/^ */  /'
grep -cE '^ +[0-9]+ +(Net|Instance|Port) ' <<< "$top" | sed 's/^/discrepancies: /'
grep -E '^ +(Error|Warning):' <<< "$top" | sort | uniq -c | sed 's/^ */  /'
