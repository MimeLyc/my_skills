#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: infer-design-ref.sh --plan <path-to-plan.md>

Find the best matching design file (usually *-design.md) for the given plan.
Outputs absolute path on success.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

plan_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      plan_path="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$plan_path" ]]; then
  echo "--plan is required" >&2
  exit 1
fi

if [[ ! -f "$plan_path" ]]; then
  echo "Plan not found: $plan_path" >&2
  exit 1
fi

plan_abs="$(cd "$(dirname "$plan_path")" && pwd)/$(basename "$plan_path")"
plan_dir="$(dirname "$plan_abs")"
plan_base="$(basename "$plan_abs" .md)"

plan_date=""
plan_topic="$plan_base"
if [[ "$plan_base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})-(.+)$ ]]; then
  plan_date="${BASH_REMATCH[1]}"
  plan_topic="${BASH_REMATCH[2]}"
fi

# Trim common plan suffixes before matching tokens.
plan_topic="${plan_topic%-implementation}"
plan_topic="${plan_topic%-plan}"
plan_topic="${plan_topic%-execution}"
plan_topic="${plan_topic%-tasks}"

get_mtime() {
  local path="$1"
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
    return
  fi
  if stat -c %Y "$path" >/dev/null 2>&1; then
    stat -c %Y "$path"
    return
  fi
  echo 0
}

token_overlap() {
  local left="$1"
  local right="$2"
  local left_file
  local right_file
  local overlap

  left_file="$(mktemp)"
  right_file="$(mktemp)"

  printf "%s\n" "$left" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | sed '/^$/d' | sort -u >"$left_file"
  printf "%s\n" "$right" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | sed '/^$/d' | sort -u >"$right_file"

  overlap="$(comm -12 "$left_file" "$right_file" | wc -l | tr -d ' ')"

  rm -f "$left_file" "$right_file"
  echo "$overlap"
}

candidates=()
while IFS= read -r candidate; do
  candidates+=("$candidate")
done < <(find "$plan_dir" -maxdepth 1 -type f -name '*-design.md' | sort)
if (( ${#candidates[@]} == 0 )); then
  echo "No design files found in $plan_dir" >&2
  exit 2
fi

plan_mtime="$(get_mtime "$plan_abs")"

best_signal_path=""
best_signal_score=-1
best_signal_mtime=0

fallback_older_path=""
fallback_older_mtime=0
fallback_any_path=""
fallback_any_mtime=0

for candidate in "${candidates[@]}"; do
  if [[ "$candidate" == "$plan_abs" ]]; then
    continue
  fi

  candidate_base="$(basename "$candidate" .md)"
  candidate_topic="$candidate_base"
  candidate_date=""

  if [[ "$candidate_base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})-(.+)-design$ ]]; then
    candidate_date="${BASH_REMATCH[1]}"
    candidate_topic="${BASH_REMATCH[2]}"
  elif [[ "$candidate_base" =~ ^(.+)-design$ ]]; then
    candidate_topic="${BASH_REMATCH[1]}"
  fi

  overlap="$(token_overlap "$plan_topic" "$candidate_topic")"
  score=$(( overlap * 10 ))
  same_date=0
  if [[ -n "$plan_date" && "$candidate_date" == "$plan_date" ]]; then
    score=$(( score + 100 ))
    same_date=1
  fi

  candidate_mtime="$(get_mtime "$candidate")"

  if (( candidate_mtime <= plan_mtime )) && (( candidate_mtime > fallback_older_mtime )); then
    fallback_older_mtime="$candidate_mtime"
    fallback_older_path="$candidate"
  fi
  if (( candidate_mtime > fallback_any_mtime )); then
    fallback_any_mtime="$candidate_mtime"
    fallback_any_path="$candidate"
  fi

  has_signal=0
  if (( same_date == 1 )) || (( overlap > 0 )); then
    has_signal=1
  fi

  if (( has_signal == 1 )); then
    if (( score > best_signal_score )); then
      best_signal_score="$score"
      best_signal_mtime="$candidate_mtime"
      best_signal_path="$candidate"
    elif (( score == best_signal_score )) && (( candidate_mtime > best_signal_mtime )); then
      best_signal_mtime="$candidate_mtime"
      best_signal_path="$candidate"
    fi
  fi
done

if [[ -n "$best_signal_path" ]]; then
  echo "$best_signal_path"
  exit 0
fi

if [[ -n "$fallback_older_path" ]]; then
  echo "$fallback_older_path"
  exit 0
fi

if [[ -n "$fallback_any_path" ]]; then
  echo "$fallback_any_path"
  exit 0
fi

echo "Unable to infer design reference for $plan_abs" >&2
exit 2
