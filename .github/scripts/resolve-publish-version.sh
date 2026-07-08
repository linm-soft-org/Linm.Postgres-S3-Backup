#!/usr/bin/env bash
# SSOT — copy to {repo}/.github/scripts/resolve-publish-version.sh (keep in sync)
# Rule: common/rule/workflow-package-version-bump.md
set -euo pipefail

collect_bump_context_text() {
  local msg="${HEAD_COMMIT_MESSAGE:-}"
  local branch=""
  local pr_title=""

  if [[ "$msg" == Merge\ pull\ request* ]]; then
    local rest="${msg#*from */}"
    rest="${rest%%$'\n'*}"
    branch="${rest%% *}"
  fi

  if command -v gh >/dev/null 2>&1 \
    && [ -n "${GITHUB_REPOSITORY:-}" ] \
    && [ -n "${GITHUB_SHA:-}" ]; then
    pr_title=$(gh api -H "Accept: application/vnd.github+json" \
      "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls" \
      --jq '.[0].title // empty' 2>/dev/null) || pr_title=""
  fi

  printf '%s' "${pr_title} ${msg} ${branch}"
}

current="${CURRENT:-}"
if [ -z "$current" ] && [ "${1:-}" != "" ]; then
  current="$1"
fi
if [ -z "$current" ]; then
  echo "::error::CURRENT version is required (env CURRENT or arg1)" >&2
  exit 1
fi

github_ref="${GITHUB_REF:-}"
ref_name="${GITHUB_REF_NAME:-}"
tag_prefix="${TAG_PREFIX:-v}"

if [[ "$github_ref" == refs/tags/* ]]; then
  if [[ -n "$tag_prefix" && "$ref_name" == "${tag_prefix}"* ]]; then
    version="${ref_name#"$tag_prefix"}"
  elif [[ "$ref_name" == v* ]]; then
    version="${ref_name#v}"
  else
    version="$ref_name"
  fi
  bump_kind=tag
  source=tag
else
  text="${BUMP_CONTEXT_TEXT:-}"
  if [ -z "$text" ]; then
    text=$(collect_bump_context_text)
  fi

  # workflow_dispatch input version (org reset e.g. 1.0.0 — Apply + commit package.json)
  if [ -n "${PUBLISH_VERSION:-}" ]; then
    if ! echo "$PUBLISH_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
      echo "::error::PUBLISH_VERSION must be semver X.Y.Z (optional -prerelease suffix)" >&2
      exit 1
    fi
    version="$PUBLISH_VERSION"
    bump_kind=explicit
    source=dispatch
  elif [ "${PUBLISH_AT_CURRENT_VERSION:-}" = "1" ] \
    || echo "$text" | grep -qiE '\[skip version bump\]|\[Publish at version\]'; then
    version="$current"
    bump_kind=fixed
    source=fixed
  else
  IFS=. read -r x y z <<< "$current"
  y=${y:-0}
  z=${z:-0}
  if [ -z "${x:-}" ]; then
    x=1
  fi

  # Major 0 — no silent 0.y bump; hard bump to 1.0.0 only when explicitly allowed
  if [ "$x" = "0" ]; then
    if [ "${HARD_BUMP_TO_STABLE:-}" = "1" ]; then
      version="1.0.0"
      bump_kind=hard_stable
      source=branch
    else
      echo "::error::Version ${current} has major 0 (x=0). Confirm hard bump to 1.0.0 (AskQuestion /github-workflows Step 2b.1), set Version in repo, or set HARD_BUMP_TO_STABLE=1 on the workflow run." >&2
      exit 1
    fi
  else
    # Default = feature (y+1, z=0) — never fail when prefix absent
    bump_kind=feature
    if echo "$text" | grep -qiE '\[Big change\]|\[Required Migration\]'; then
      bump_kind=big
      x=$((x + 1))
      y=0
      z=0
    elif echo "$text" | grep -qiE '\[Bug\]|\[Issue\]'; then
      bump_kind=bug
      z=$((z + 1))
    else
      y=$((y + 1))
      z=0
    fi
    version="${x}.${y}.${z}"
    source=branch
  fi
  fi
fi

echo "Resolved: ${current} → ${version} (${bump_kind})"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${version}"
    echo "current=${current}"
    echo "source=${source}"
    echo "bump_kind=${bump_kind}"
  } >> "$GITHUB_OUTPUT"
else
  printf '%s\n' "$version"
fi
