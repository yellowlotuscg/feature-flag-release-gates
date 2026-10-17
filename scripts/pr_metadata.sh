#!/usr/bin/env bash
set -euo pipefail

# Build the input consumed by policy/pr.rego. The merge queue admission bit is
# supplied by the caller because GitHub's PR API does not expose queue state.
out="${1:-pr-metadata.json}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
pr_number="${PR_NUMBER:-}"
if [[ -z "$pr_number" && -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
  pr_number="$(jq -r '.number // .pull_request.number // empty' "$GITHUB_EVENT_PATH")"
fi
: "${pr_number:?PR_NUMBER or a pull_request event is required}"

pr_json="$(gh api "repos/$repo/pulls/$pr_number")"
reviews_json="$(gh api --paginate "repos/$repo/pulls/$pr_number/reviews" | jq -s 'add // []')"
files_json="$(gh api --paginate "repos/$repo/pulls/$pr_number/files" | jq -s 'add // [] | map(.filename)')"
checks_json="$(gh api "repos/$repo/commits/$(jq -r '.head.sha' <<<"$pr_json")/check-runs" --jq '[.check_runs[] | {name: .name, conclusion: (.conclusion // .status)}]')"
labels_json="$(jq -c '[.labels[].name]' <<<"$pr_json")"
owners_json="$(awk 'NF && $1 !~ /^#/ {for (i=2; i<=NF; i++) if ($i ~ /^@/) {gsub(/^@/, "", $i); print $i}}' .github/CODEOWNERS 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))')"
if [[ -n "${REQUIRED_CHECKS_JSON:-}" ]]; then
  required_checks="$REQUIRED_CHECKS_JSON"
else
  required_checks='["build-test","policy","gitleaks","deny-list","bicep-build","python-audit"]'
fi
merge_queue="${PR_MERGE_QUEUE:-false}"

jq -n \
  --arg author "$(jq -r '.user.login' <<<"$pr_json")" \
  --arg base "$(jq -r '.base.ref' <<<"$pr_json")" \
  --argjson queue "$merge_queue" \
  --argjson labels "$labels_json" \
  --argjson files "$files_json" \
  --argjson owners "$owners_json" \
  --argjson reviews "$(jq '[.[] | {user_login: .user.login, state: .state}]' <<<"$reviews_json")" \
  --argjson required "$required_checks" \
  --argjson checks "$checks_json" \
  '{pull_request: {author_login: $author, base_ref: $base, merge_queue: $queue, labels: $labels, changed_files: $files}, codeowners: $owners, reviews: $reviews, required_checks: $required, checks: $checks}' \
  > "$out"

printf 'Wrote %s\n' "$out"
