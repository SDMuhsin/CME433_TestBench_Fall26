#!/usr/bin/env bash
# Digest of a Calibre LVS report (stdout): overall result, cell/net/instance counts,
# discrepancy and extraction warning counts (no cell names).
rep=$1
echo "calibre lvs digest of $(basename "$rep")"
grep -m1 -E 'CORRECT|INCORRECT|NOT COMPARED' "$rep" | sed 's/^ */result: /'
grep -E '^\s*(Nets|Instances|Ports|Total Inst):' "$rep" | head -8 | sed 's/^ */  /'
grep -cE '^\s*[0-9]+\s+(Net|Instance|Port)' "$rep" | sed 's/^/discrepancy lines: /'
grep -E 'LVS (BOX|Shorts|Softchk)|Error|Warning' "$rep" | sort | uniq -c | head -10 | sed 's/^/  /'
