#!/usr/bin/env bash
set -euo pipefail

list=".github/denylist.txt"
if [[ ! -f "$list" ]]; then
  echo "No deny-list file configured; skipping deny-list scan."
  exit 0
fi

status=0
while IFS= read -r term || [[ -n "$term" ]]; do
  [[ -z "$term" || "$term" == \#* ]] && continue
  while IFS= read -r -d '' file; do
    [[ "$file" == "$list" ]] && continue
    if grep -n -F -i -- "$term" "$file" >/dev/null 2>&1; then
      echo "deny-list term '$term' found in $file"
      grep -n -F -i -- "$term" "$file" || true
      status=1
    fi
  done < <(git ls-files -z)
done < "$list"
exit "$status"
