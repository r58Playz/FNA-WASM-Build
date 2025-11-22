#!/usr/bin/env bash

arfile="$1"
outfile="$2"

{
    echo "// Auto-generated symbol rename header"
    echo "// From: $arfile"
    echo

    # llvm-nm default output:  <address> <type> <symbol>
    # We keep only global defined symbols and extract the 3rd column.
    llvm-nm --extern-only --defined-only "$arfile" \
    | awk '{ print $3 }' \
    | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' \
    | sort -u \
    | while read -r sym; do
        echo "#define ${sym} SDL3_renamed_${sym}"
      done
} > "$outfile"

echo "Wrote $outfile"
