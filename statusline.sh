#!/usr/bin/env bash

input=$(cat)

CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

rgb() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
fmt_time() { date -r "$1" +"$2" 2>/dev/null || date -d "@$1" +"$2" 2>/dev/null; }
lim_color() {
  if [ "$1" -ge 90 ]; then echo "$RED"
  elif [ "$1" -ge 70 ]; then echo "$YELLOW"
  else echo "$GREEN"; fi
}
json_num() {
  local re="\"$2\"[[:space:]]*:[[:space:]]*(-?[0-9.]+([eE][+-]?[0-9]+)?)"
  [[ $1 =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
}
json_str() {
  local re="\"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  [[ $1 =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
}

model=$(json_str "$input" display_name)
model=${model:-Unknown}
cost=$(json_num "$input" total_cost_usd)
cost=${cost:-0}
lines_add=$(json_num "$input" total_lines_added)
lines_add=${lines_add:-0}
lines_del=$(json_num "$input" total_lines_removed)
lines_del=${lines_del:-0}
cwd=$(json_str "$input" current_dir)
[ -z "$cwd" ] && cwd=$(json_str "$input" cwd)

used=""
if [[ $input == *'"context_window"'* ]]; then
  ctx_chunk=${input#*\"context_window\"}
  ctx_chunk=${ctx_chunk%%\"rate_limits\"*}
  used=$(json_num "$ctx_chunk" used_percentage)
fi

branch=""
repo=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  repo=$(basename "$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
fi

BAR_WIDTH=20

if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  filled=$(( (used_int * BAR_WIDTH + 50) / 100 ))

  bar=""
  for (( i=0; i<BAR_WIDTH; i++ )); do
    pos=$(( i * 100 / (BAR_WIDTH - 1) ))
    if [ "$pos" -le 50 ]; then
      r=$(( 220 * pos / 50 ))
      g=200
      b=$(( 80 - 80 * pos / 50 ))
    else
      adj=$(( pos - 50 ))
      r=220
      g=$(( 200 - 160 * adj / 50 ))
      b=$(( 20 * adj / 50 ))
    fi
    if [ "$i" -lt "$filled" ]; then
      bar="${bar}$(rgb $r $g $b)█"
    else
      bar="${bar}\033[38;2;60;60;60m░"
    fi
  done
  bar="${bar}${RESET}"

  if [ "$used_int" -ge 90 ]; then status_emoji="🚨"; hint="compact now"
  elif [ "$used_int" -ge 70 ]; then status_emoji="🔥"; hint="wrap up soon"
  elif [ "$used_int" -ge 20 ]; then status_emoji="⚡"; hint="ok"
  else status_emoji="🟢"; hint="fresh"; fi

  if [ "$used_int" -ge 90 ]; then pct_color="$RED"
  elif [ "$used_int" -ge 70 ]; then pct_color="$YELLOW"
  else pct_color="$GREEN"; fi

  ctx_part="${status_emoji} ${bar} ${pct_color}${used_int}%${RESET} ${DIM}${hint}${RESET}"
else
  ctx_part="🟢 \033[38;2;60;60;60m░░░░░░░░░░░░░░░░░░░░${RESET} --%"
fi

cost_part="${YELLOW}$(printf '$%.2f' "$cost")${RESET}"
velocity="${GREEN}+${lines_add}${RESET} ${RED}-${lines_del}${RESET}"

limits=""
lim_warn=""
if [[ $input == *'"five_hour"'* ]]; then
  chunk=${input#*\"five_hour\"}
  chunk=${chunk%%\}*}
  p=$(json_num "$chunk" used_percentage)
  if [ -n "$p" ]; then
    p=$(printf '%.0f' "$p")
    reset_at=$(json_num "$chunk" resets_at)
    limits="5h $(lim_color "$p")${p}%${RESET}"
    [ -n "$reset_at" ] && limits="${limits} ${DIM}resets $(fmt_time "$reset_at" %H:%M)${RESET}"
    [ "$p" -ge 90 ] && lim_warn=" ${RED}⚠ near limit, pause until reset${RESET}"
  fi
fi
if [[ $input == *'"seven_day"'* ]]; then
  chunk=${input#*\"seven_day\"}
  chunk=${chunk%%\}*}
  p=$(json_num "$chunk" used_percentage)
  if [ -n "$p" ]; then
    p=$(printf '%.0f' "$p")
    reset_at=$(json_num "$chunk" resets_at)
    limits="${limits:+$limits ${DIM}·${RESET} }7d $(lim_color "$p")${p}%${RESET}"
    [ -n "$reset_at" ] && limits="${limits} ${DIM}resets $(fmt_time "$reset_at" '%a %H:%M')${RESET}"
    [ "$p" -ge 90 ] && lim_warn=" ${RED}⚠ near limit, pause until reset${RESET}"
  fi
fi
limits="${limits}${lim_warn}"

out=""
[ -n "$repo" ] && out="${BOLD}${YELLOW}${repo}${RESET}"
[ -n "$branch" ] && out="${out:+$out }${BOLD}${CYAN}🌿 (${branch})${RESET}"
out="${out:+$out ${DIM}|${RESET} }${ctx_part}"
out="${out} ${DIM}|${RESET} ${cost_part}"
out="${out} ${DIM}|${RESET} ${velocity}"
[ -n "$limits" ] && out="${out} ${DIM}|${RESET} ⏱ ${limits}"
out="${out} ${DIM}|${RESET} ${MAGENTA}🤖 ${model}${RESET}"

printf '%b' "$out"
