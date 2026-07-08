#!/usr/bin/env bash
# Apply all branch rulesets under .github/rulesets/*.json
# Rule: common/rule/github-branch-ruleset.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RULESETS_DIR="${REPO_ROOT}/.github/rulesets"

if ! command -v gh >/dev/null 2>&1; then
  echo "::error::Missing gh CLI. Install: https://cli.github.com/"
  exit 1
fi

if [ ! -d "$RULESETS_DIR" ]; then
  echo "::error::Not found: $RULESETS_DIR"
  exit 1
fi

REMOTE_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
else
  echo "::error::Cannot parse owner/repo from origin: $REMOTE_URL"
  exit 1
fi

echo "Repository: ${OWNER}/${REPO}"

# GitHub Actions bypass — only for main publish ruleset (npm/NuGet lib with publish workflow)
ACTIONS_ID="$(gh api "repos/${OWNER}/${REPO}/rulesets/bypass-actors" 2>/dev/null | jq -r '.[] | select(.name=="GitHub Actions") | .id' 2>/dev/null || true)"
if [ -z "$ACTIONS_ID" ] || [ "$ACTIONS_ID" = "null" ]; then
  ACTIONS_ID="$(gh api orgs/"${OWNER}"/rulesets/bypass-actors 2>/dev/null | jq -r '.[] | select(.name=="GitHub Actions") | .id' 2>/dev/null || true)"
fi

apply_ruleset() {
  local json_file="$1"
  local ruleset_name
  ruleset_name="$(jq -r '.name' "$json_file")"
  local payload
  payload="$(mktemp)"

  if [[ "$(basename "$json_file")" == "main-require-pr-and-ci.json" ]] \
    && [[ -f "${REPO_ROOT}/.github/workflows/publish.yml" || -f "${REPO_ROOT}/.github/workflows/publish-nuget.yml" ]] \
    && [ -n "$ACTIONS_ID" ] && [ "$ACTIONS_ID" != "null" ]; then
    jq --argjson id "$ACTIONS_ID" \
      '.bypass_actors = [{ "actor_id": $id, "actor_type": "Integration", "bypass_mode": "always" }]' \
      "$json_file" > "$payload"
    echo "  bypass: GitHub Actions (${ACTIONS_ID})"
  else
    cp "$json_file" "$payload"
  fi

  local existing_id
  existing_id="$(gh api "repos/${OWNER}/${REPO}/rulesets" --jq ".[] | select(.name==\"${ruleset_name}\") | .id" 2>/dev/null || true)"

  if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
    echo "Updating ruleset '${ruleset_name}' (id ${existing_id})..."
    gh api --method PUT "repos/${OWNER}/${REPO}/rulesets/${existing_id}" --input "$payload"
  else
    echo "Creating ruleset '${ruleset_name}'..."
    gh api --method POST "repos/${OWNER}/${REPO}/rulesets" --input "$payload"
  fi

  rm -f "$payload"
}

shopt -s nullglob
files=("$RULESETS_DIR"/*.json)
if [ ${#files[@]} -eq 0 ]; then
  echo "::error::No ruleset JSON in $RULESETS_DIR"
  exit 1
fi

for json_file in "${files[@]}"; do
  echo "--- $(basename "$json_file")"
  apply_ruleset "$json_file"
done

if [[ -f "${REPO_ROOT}/.github/workflows/publish.yml" || -f "${REPO_ROOT}/.github/workflows/publish-nuget.yml" ]] \
  && { [ -z "$ACTIONS_ID" ] || [ "$ACTIONS_ID" = "null" ]; }; then
  echo "::warning::Could not resolve GitHub Actions bypass actor id."
  echo "After apply: Rulesets → 'main — require PR and CI / build' → add bypass 'GitHub Actions' (always)."
fi

echo "Done. Verify: https://github.com/${OWNER}/${REPO}/settings/rules"
