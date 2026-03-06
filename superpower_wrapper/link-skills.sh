#!/usr/bin/env bash
set -euo pipefail

script_name="$(basename "$0")"
source_dir="$PWD"
target_opt="codex"
target_dir=""
force=0
dry_run=0
include_hidden=0

usage() {
  cat <<USAGE
Usage: $script_name [options]

Link all first-level directories from a source directory into a target skills directory.

Options:
  -t, --target <codex|claude|PATH>  Target preset or custom path (default: codex)
  -s, --source <PATH>               Source directory to scan (default: current directory)
  -f, --force                       Remove existing destination path before linking
  -n, --dry-run                     Print actions without modifying files
      --include-hidden              Include hidden directories (default: off)
  -h, --help                        Show this help

Examples:
  $script_name
  $script_name --target claude
  $script_name --target ~/my/skills --source ./my_skills --dry-run
USAGE
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

expand_path() {
  local p="$1"
  case "$p" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${p#~/}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

resolve_target_dir() {
  local input="$1"
  case "$input" in
    codex) printf '%s\n' "$HOME/.codex/skills" ;;
    claude) printf '%s\n' "$HOME/.claude/skills" ;;
    *) expand_path "$input" ;;
  esac
}

run_cmd() {
  if ((dry_run)); then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      target_opt="$2"
      shift 2
      ;;
    -s|--source)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      source_dir="$2"
      shift 2
      ;;
    -f|--force)
      force=1
      shift
      ;;
    -n|--dry-run)
      dry_run=1
      shift
      ;;
    --include-hidden)
      include_hidden=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

source_dir="$(expand_path "$source_dir")"
[[ -d "$source_dir" ]] || die "Source directory not found: $source_dir"
source_dir="$(cd "$source_dir" && pwd)"

target_dir="$(resolve_target_dir "$target_opt")"
if [[ "$target_dir" != /* ]]; then
  target_dir="$PWD/$target_dir"
fi

if ((dry_run)); then
  printf '[dry-run] mkdir -p %s\n' "$target_dir"
else
  mkdir -p "$target_dir"
fi

created=0
skipped=0
failed=0

while IFS= read -r src; do
  name="$(basename "$src")"
  dest="$target_dir/$name"

  if [[ "$src" == "$target_dir" ]]; then
    printf 'Skip: source dir equals target dir: %s\n' "$src"
    ((skipped += 1))
    continue
  fi

  if [[ -L "$dest" ]]; then
    current_target="$(readlink "$dest" || true)"
    if [[ "$current_target" == "$src" ]]; then
      printf 'Skip: already linked %s -> %s\n' "$dest" "$src"
      ((skipped += 1))
      continue
    fi
  fi

  if [[ -e "$dest" || -L "$dest" ]]; then
    if ((force)); then
      run_cmd rm -rf "$dest"
    else
      printf 'Skip: destination exists (use --force): %s\n' "$dest"
      ((skipped += 1))
      continue
    fi
  fi

  if ((dry_run)); then
    run_cmd ln -s "$src" "$dest"
    printf 'Planned: %s -> %s\n' "$dest" "$src"
    ((created += 1))
  else
    if ln -s "$src" "$dest"; then
      printf 'Linked: %s -> %s\n' "$dest" "$src"
      ((created += 1))
    else
      printf 'Failed: %s -> %s\n' "$dest" "$src" >&2
      ((failed += 1))
    fi
  fi
done < <(
  if ((include_hidden)); then
    find "$source_dir" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort
  else
    find "$source_dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | LC_ALL=C sort
  fi
)

printf '\nSummary: created=%d skipped=%d failed=%d target=%s\n' "$created" "$skipped" "$failed" "$target_dir"

if ((failed > 0)); then
  exit 1
fi
