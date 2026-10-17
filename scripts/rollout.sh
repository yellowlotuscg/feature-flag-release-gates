#!/usr/bin/env bash
set -euo pipefail

APP_CONFIG_NAME="${APP_CONFIG_NAME:-northwind-pricing-config}"
LABEL="${LABEL:-production}"
DRY_RUN="${DRY_RUN:-1}"

if [[ "$DRY_RUN" != "1" && "$DRY_RUN" != "0" ]]; then
  echo "DRY_RUN must be 0 or 1" >&2
  exit 2
fi

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  if [[ "$DRY_RUN" == "0" ]]; then
    "$@"
  fi
}

set_flag() {
  local name="$1" enabled="$2" action
  if [[ "$enabled" == "true" ]]; then
    action=enable
  else
    action=disable
  fi
  run az appconfig feature "$action" \
    --name "$APP_CONFIG_NAME" \
    --feature "$name" \
    --label "$LABEL" \
    --auth-mode login \
    --yes
}

set_targeting() {
  local name="$1" default_percentage="$2" group_percentage="$3"
  local audience
  audience=$(printf '{"Users":[],"Groups":[{"Name":"internal","RolloutPercentage":%s}],"DefaultRolloutPercentage":%s}' "$group_percentage" "$default_percentage")
  run az appconfig feature filter delete \
    --name "$APP_CONFIG_NAME" --feature "$name" --label "$LABEL" \
    --filter-name Microsoft.Targeting --auth-mode login --yes || true
  run az appconfig feature filter add \
    --name "$APP_CONFIG_NAME" --feature "$name" --label "$LABEL" \
    --filter-name Microsoft.Targeting --filter-parameters "Audience=$audience" \
    --auth-mode login --yes
}

stage="${1:-10}"
case "$stage" in
  internal)
    set_flag VolumeDiscounts true
    set_flag RegionalTax true
    set_targeting VolumeDiscounts 0 100
    set_targeting RegionalTax 0 100
    set_flag KillSwitch false
    echo "Internal group is enabled with zero default rollout."
    ;;
  10)
    set_flag VolumeDiscounts true
    set_flag RegionalTax true
    set_targeting VolumeDiscounts 10 100
    set_targeting RegionalTax 10 100
    set_flag KillSwitch false
    echo "Internal group is enabled plus a deterministic ten percent default rollout."
    ;;
  100)
    set_flag VolumeDiscounts true
    set_flag RegionalTax true
    set_targeting VolumeDiscounts 100 100
    set_targeting RegionalTax 100 100
    set_flag KillSwitch false
    echo "All users are enabled by the targeting filter."
    ;;
  kill)
    set_flag KillSwitch true
    echo "Kill switch enabled; the API will ignore all other features after refresh."
    ;;
  *)
    echo "Usage: $0 {internal|10|100|kill}" >&2
    exit 2
    ;;
esac
