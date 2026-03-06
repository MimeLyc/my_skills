#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: sync-plan-status.sh --plan <path-to-plan.md> --event <event> [options]

Events:
  task_started
  task_completed
  task_blocked
  plan_completed

Options:
  --task-id <TNN|NN>     Optional task id for task_* events
  --task-title <text>    Optional text to record with blocked event
  --mode <name>          Optional execution mode metadata (stored nowhere for now)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

plan_path=""
event_name=""
task_id_raw=""
task_title=""
mode_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      plan_path="${2:-}"
      shift 2
      ;;
    --event)
      event_name="${2:-}"
      shift 2
      ;;
    --task-id)
      task_id_raw="${2:-}"
      shift 2
      ;;
    --task-title)
      task_title="${2:-}"
      shift 2
      ;;
    --mode)
      mode_name="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$plan_path" || -z "$event_name" ]]; then
  echo "--plan and --event are required" >&2
  exit 1
fi

case "$event_name" in
  task_started|task_completed|task_blocked|plan_completed)
    ;;
  *)
    echo "Unsupported event: $event_name" >&2
    exit 1
    ;;
esac

if [[ ! -f "$plan_path" ]]; then
  echo "Plan not found: $plan_path" >&2
  exit 1
fi

plan_abs="$(cd "$(dirname "$plan_path")" && pwd)/$(basename "$plan_path")"
plan_dir="$(dirname "$plan_abs")"
plan_file_name="$(basename "$plan_abs")"
plan_name="${plan_file_name%.md}"

status_start="<!-- plan-progress-sync:status:start -->"
status_end="<!-- plan-progress-sync:status:end -->"
tasks_start="<!-- plan-progress-sync:tasks:start -->"
tasks_end="<!-- plan-progress-sync:tasks:end -->"

TMP_FILES=()
cleanup() {
  if (( ${#TMP_FILES[@]} > 0 )); then
    rm -f "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

new_tmp() {
  local t
  t="$(mktemp)"
  TMP_FILES+=("$t")
  printf "%s" "$t"
}

resolve_project_root() {
  local plan="$1"
  local dir
  dir="$(dirname "$plan")"

  if [[ "$plan" == *"/docs/plans/"* ]]; then
    printf "%s" "${plan%/docs/plans/*}"
    return
  fi

  if git -C "$dir" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$dir" rev-parse --show-toplevel
    return
  fi

  printf "%s" "$dir"
}

project_root="$(resolve_project_root "$plan_abs")"
if [[ "$plan_abs" == "$project_root"/* ]]; then
  plan_rel="${plan_abs#"$project_root"/}"
else
  plan_rel="$plan_abs"
fi

if [[ -d "$project_root/docs/plans" ]]; then
  plans_dir="$project_root/docs/plans"
else
  plans_dir="$plan_dir"
fi
index_file="$plans_dir/INDEX.md"

normalize_task_id() {
  local raw="$1"
  raw="${raw// /}"
  raw="${raw#Task}"
  raw="${raw#task}"

  if [[ -z "$raw" ]]; then
    return 1
  fi

  if [[ "$raw" =~ ^T([0-9]{1,3})$ ]]; then
    printf "T%02d" "$((10#${BASH_REMATCH[1]}))"
    return
  fi
  if [[ "$raw" =~ ^([0-9]{1,3})$ ]]; then
    printf "T%02d" "$((10#${BASH_REMATCH[1]}))"
    return
  fi

  return 1
}

tasks_file="$(new_tmp)"
awk '
  /^### Task[[:space:]]+[0-9]+:/ {
    line = $0
    sub(/^### Task[[:space:]]+/, "", line)
    title = line
    sub(/^[0-9]+:[[:space:]]*/, "", title)
    split(line, parts, ":")
    task_num = parts[1] + 0
    printf "T%02d|%s\n", task_num, title
  }
' "$plan_abs" >"$tasks_file"

total_tasks="$(wc -l <"$tasks_file" | tr -d ' ')"

has_task_id() {
  local id="$1"
  grep -q "^${id}|" "$tasks_file"
}

done_file="$(new_tmp)"
awk -v s="$tasks_start" -v e="$tasks_end" '
  $0 == s { in_block = 1; next }
  $0 == e { in_block = 0; next }
  in_block {
    if ($0 ~ /^- \[[xX]\] T[0-9][0-9][0-9]*[[:space:]]/) {
      line = $0
      sub(/^- \[[xX]\] /, "", line)
      split(line, parts, /[[:space:]]+/)
      print parts[1]
    }
  }
' "$plan_abs" | sort -u >"$done_file"

existing_current_task="$(awk -v s="$status_start" -v e="$status_end" '
  $0 == s { in_block = 1; next }
  $0 == e { in_block = 0; next }
  in_block && /^- Current Task:/ {
    sub(/^- Current Task:[[:space:]]*/, "", $0)
    print $0
    exit
  }
' "$plan_abs")"

existing_design_ref="$(awk -v s="$status_start" -v e="$status_end" '
  $0 == s { in_block = 1; next }
  $0 == e { in_block = 0; next }
  in_block && /^- Design Ref:/ {
    sub(/^- Design Ref:[[:space:]]*/, "", $0)
    print $0
    exit
  }
' "$plan_abs")"

if [[ -z "$existing_design_ref" ]]; then
  existing_design_ref="$(awk '
    /^- Design Ref:/ {
      sub(/^- Design Ref:[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$plan_abs")"
fi

is_done() {
  local id="$1"
  grep -qx "$id" "$done_file"
}

mark_done() {
  local id="$1"
  if [[ -z "$id" ]]; then
    return
  fi
  if ! grep -qx "$id" "$done_file"; then
    echo "$id" >>"$done_file"
    sort -u -o "$done_file" "$done_file"
  fi
}

first_unchecked_task() {
  local id
  local title
  while IFS='|' read -r id title; do
    if [[ -n "$id" ]] && ! is_done "$id"; then
      printf "%s" "$id"
      return
    fi
  done <"$tasks_file"
}

resolved_task_id=""
if [[ -n "$task_id_raw" ]]; then
  if ! resolved_task_id="$(normalize_task_id "$task_id_raw")"; then
    echo "Invalid task id: $task_id_raw" >&2
    exit 1
  fi
  if ! has_task_id "$resolved_task_id"; then
    echo "Task id not found in plan: $resolved_task_id" >&2
    exit 1
  fi
fi

if [[ -n "$existing_current_task" && "$existing_current_task" != "-" ]]; then
  if normalized_existing="$(normalize_task_id "$existing_current_task" 2>/dev/null)"; then
    existing_current_task="$normalized_existing"
  fi
fi

current_task="-"

case "$event_name" in
  task_started)
    if [[ -z "$resolved_task_id" ]]; then
      resolved_task_id="$(first_unchecked_task || true)"
    fi
    current_task="${resolved_task_id:--}"
    ;;
  task_completed)
    if [[ -z "$resolved_task_id" ]]; then
      if [[ -n "$existing_current_task" && "$existing_current_task" != "-" ]] && has_task_id "$existing_current_task"; then
        resolved_task_id="$existing_current_task"
      else
        resolved_task_id="$(first_unchecked_task || true)"
      fi
    fi
    if [[ -n "$resolved_task_id" ]]; then
      mark_done "$resolved_task_id"
    fi
    next_task="$(first_unchecked_task || true)"
    current_task="${next_task:--}"
    ;;
  task_blocked)
    if [[ -z "$resolved_task_id" ]]; then
      resolved_task_id="$existing_current_task"
    fi
    current_task="${resolved_task_id:--}"
    ;;
  plan_completed)
    while IFS='|' read -r task_id _; do
      if [[ -n "$task_id" ]]; then
        mark_done "$task_id"
      fi
    done <"$tasks_file"
    current_task="-"
    ;;
esac

done_count=0
while IFS='|' read -r task_id _; do
  if [[ -n "$task_id" ]] && is_done "$task_id"; then
    done_count=$((done_count + 1))
  fi
done <"$tasks_file"

if (( total_tasks > 0 )); then
  progress_text="${done_count}/${total_tasks}"
else
  progress_text="0/0"
fi

plan_status="ready"
case "$event_name" in
  task_blocked)
    plan_status="blocked"
    ;;
  plan_completed)
    plan_status="done"
    ;;
  *)
    if (( total_tasks > 0 && done_count >= total_tasks )); then
      plan_status="done"
    elif (( done_count > 0 )) || [[ "$event_name" == "task_started" || "$event_name" == "task_completed" ]]; then
      plan_status="in_progress"
    else
      plan_status="ready"
    fi
    ;;
esac

blocker_text="none"
if [[ "$event_name" == "task_blocked" ]]; then
  if [[ -n "$task_title" ]]; then
    blocker_text="$task_title"
  elif [[ "$current_task" != "-" ]]; then
    blocker_text="Task $current_task blocked"
  else
    blocker_text="blocked"
  fi
fi

resolve_existing_design_ref() {
  local ref="$1"
  if [[ -z "$ref" || "$ref" == "unresolved" ]]; then
    return 1
  fi

  if [[ "$ref" = /* && -f "$ref" ]]; then
    printf "%s" "$ref"
    return
  fi

  if [[ -f "$project_root/$ref" ]]; then
    printf "%s" "$project_root/$ref"
    return
  fi

  if [[ -f "$plan_dir/$ref" ]]; then
    printf "%s" "$plan_dir/$ref"
    return
  fi

  return 1
}

design_abs=""
if design_abs="$(resolve_existing_design_ref "$existing_design_ref" 2>/dev/null)"; then
  :
else
  infer_script="$(cd "$(dirname "$0")" && pwd)/infer-design-ref.sh"
  if design_abs="$("$infer_script" --plan "$plan_abs" 2>/dev/null)"; then
    :
  else
    design_abs=""
  fi
fi

design_ref="unresolved"
if [[ -n "$design_abs" ]]; then
  if [[ "$design_abs" == "$project_root"/* ]]; then
    design_ref="${design_abs#"$project_root"/}"
  else
    design_ref="$design_abs"
  fi
else
  plan_status="blocked"
  blocker_text="Design reference unresolved"
fi

updated_at="$(date '+%Y-%m-%d %H:%M')"

status_content_file="$(new_tmp)"
cat >"$status_content_file" <<STATUS
## Execution Status
- Plan Status: $plan_status
- Progress: $progress_text
- Current Task: $current_task
- Design Ref: $design_ref
- Last Updated: $updated_at
- Blocker: $blocker_text
STATUS

tasks_content_file="$(new_tmp)"
{
  echo "## Task Status"
  echo ""
  while IFS='|' read -r task_id task_title_line; do
    [[ -z "$task_id" ]] && continue
    checkbox=" "
    if is_done "$task_id"; then
      checkbox="x"
    fi
    if [[ -z "$task_title_line" ]]; then
      task_title_line="(untitled)"
    fi
    printf -- "- [%s] %s %s\n" "$checkbox" "$task_id" "$task_title_line"
  done <"$tasks_file"
} >"$tasks_content_file"

upsert_block() {
  local file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local content_file="$4"
  local position="$5"
  local tmp_file
  tmp_file="$(new_tmp)"

  if grep -qF "$start_marker" "$file"; then
    awk -v s="$start_marker" -v e="$end_marker" -v cfile="$content_file" '
      BEGIN {
        while ((getline line < cfile) > 0) {
          content = content line "\n"
        }
        close(cfile)
        in_block = 0
      }
      {
        if ($0 == s) {
          print s
          printf "%s", content
          in_block = 1
          next
        }
        if ($0 == e) {
          in_block = 0
          print e
          next
        }
        if (!in_block) {
          print
        }
      }
    ' "$file" >"$tmp_file"
  else
    if [[ "$position" == "top" ]]; then
      awk -v s="$start_marker" -v e="$end_marker" -v cfile="$content_file" '
        BEGIN {
          while ((getline line < cfile) > 0) {
            content = content line "\n"
          }
          close(cfile)
          inserted = 0
        }
        {
          if (!inserted && /^#/) {
            print
            print ""
            print s
            printf "%s", content
            print e
            print ""
            inserted = 1
            next
          }
          print
        }
        END {
          if (!inserted) {
            print ""
            print s
            printf "%s", content
            print e
          }
        }
      ' "$file" >"$tmp_file"
    else
      cat "$file" >"$tmp_file"
      {
        echo ""
        echo "$start_marker"
        cat "$content_file"
        echo "$end_marker"
      } >>"$tmp_file"
    fi
  fi

  mv "$tmp_file" "$file"
}

upsert_block "$plan_abs" "$status_start" "$status_end" "$status_content_file" "top"
upsert_block "$plan_abs" "$tasks_start" "$tasks_end" "$tasks_content_file" "bottom"

mkdir -p "$plans_dir"

rows_file="$(new_tmp)"
if [[ -f "$index_file" ]]; then
  awk -F'|' -v target="$plan_rel" '
    /^\|/ {
      if ($0 ~ /^\|[[:space:]]*Plan[[:space:]]*\|/) next
      if ($0 ~ /^\|[[:space:]]*---/) next
      col = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", col)
      if (col == target) next
      print $0
    }
  ' "$index_file" >"$rows_file"
fi

{
  echo "# Plan Index"
  echo ""
  echo "| Plan | Status | Progress | Current Task | Design Ref | Updated |"
  echo "|---|---|---|---|---|---|"
  if [[ -s "$rows_file" ]]; then
    cat "$rows_file"
  fi
  printf "| %s | %s | %s | %s | %s | %s |\n" \
    "$plan_rel" "$plan_status" "$progress_text" "$current_task" "$design_ref" "$updated_at"
} >"$index_file"

# Keep mode_name referenced so shellcheck doesn't flag it as unused when linted.
: "$mode_name"

echo "Synced plan status: $plan_rel ($event_name)"
