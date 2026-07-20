[Console]::OutputEncoding = [Text.Encoding]::UTF8
$raw = [Console]::In.ReadToEnd()
try { $d = $raw | ConvertFrom-Json } catch { $d = $null }

$E = [char]27
$CYAN = "${E}[36m"
$GREEN = "${E}[32m"
$YELLOW = "${E}[33m"
$RED = "${E}[31m"
$MAGENTA = "${E}[35m"
$DIM = "${E}[2m"
$BOLD = "${E}[1m"
$RESET = "${E}[0m"

function Rgb($r, $g, $b) { "${E}[38;2;$r;$g;${b}m" }
function LimColor($p) {
  if ($p -ge 90) { $RED }
  elseif ($p -ge 70) { $YELLOW }
  else { $GREEN }
}
function FmtTime($epoch, $fmt) {
  [DateTimeOffset]::FromUnixTimeSeconds([long]$epoch).ToLocalTime().ToString($fmt)
}

$model = if ($d.model.display_name) { $d.model.display_name } else { 'Unknown' }
$used = $d.context_window.used_percentage
$cost = if ($d.cost.total_cost_usd) { [double]$d.cost.total_cost_usd } else { 0 }
$linesAdd = if ($d.cost.total_lines_added) { [int]$d.cost.total_lines_added } else { 0 }
$linesDel = if ($d.cost.total_lines_removed) { [int]$d.cost.total_lines_removed } else { 0 }
$cwd = if ($d.workspace.current_dir) { $d.workspace.current_dir } elseif ($d.cwd) { $d.cwd } else { '' }

$branch = ''
$repo = ''
if ($cwd -and (Get-Command git -ErrorAction SilentlyContinue)) {
  $branch = git -C $cwd --no-optional-locks symbolic-ref --short HEAD 2>$null
  $top = git -C $cwd --no-optional-locks rev-parse --show-toplevel 2>$null
  if ($top) { $repo = Split-Path $top -Leaf }
}

$BAR_WIDTH = 20

if ($null -ne $used) {
  $usedInt = [int][math]::Round([double]$used)
  $filled = [math]::Floor(($usedInt * $BAR_WIDTH + 50) / 100)

  $bar = ''
  for ($i = 0; $i -lt $BAR_WIDTH; $i++) {
    $pos = [math]::Floor($i * 100 / ($BAR_WIDTH - 1))
    if ($pos -le 50) {
      $r = [math]::Floor(220 * $pos / 50)
      $g = 200
      $b = [math]::Floor(80 - 80 * $pos / 50)
    } else {
      $adj = $pos - 50
      $r = 220
      $g = [math]::Floor(200 - 160 * $adj / 50)
      $b = [math]::Floor(20 * $adj / 50)
    }
    if ($i -lt $filled) { $bar += (Rgb $r $g $b) + '█' }
    else { $bar += "${E}[38;2;60;60;60m░" }
  }
  $bar += $RESET

  if ($usedInt -ge 90) { $emoji = '🚨'; $hint = 'compact now' }
  elseif ($usedInt -ge 70) { $emoji = '🔥'; $hint = 'wrap up soon' }
  elseif ($usedInt -ge 20) { $emoji = '⚡'; $hint = 'ok' }
  else { $emoji = '🟢'; $hint = 'fresh' }

  if ($usedInt -ge 90) { $pctColor = $RED }
  elseif ($usedInt -ge 70) { $pctColor = $YELLOW }
  else { $pctColor = $GREEN }

  $ctxPart = "${emoji} ${bar} ${pctColor}${usedInt}%${RESET} ${DIM}${hint}${RESET}"
} else {
  $ctxPart = "🟢 ${E}[38;2;60;60;60m░░░░░░░░░░░░░░░░░░░░${RESET} --%"
}

$costPart = "${YELLOW}" + ('${0:0.00}' -f $cost) + "${RESET}"
$velocity = "${GREEN}+${linesAdd}${RESET} ${RED}-${linesDel}${RESET}"

$limits = ''
$limWarn = ''
$fh = $d.rate_limits.five_hour
if ($null -ne $fh.used_percentage) {
  $p = [int][math]::Round([double]$fh.used_percentage)
  $limits = "5h $(LimColor $p)${p}%${RESET}"
  if ($fh.resets_at) { $limits += " ${DIM}resets $(FmtTime $fh.resets_at 'HH:mm')${RESET}" }
  if ($p -ge 90) { $limWarn = " ${RED}⚠ near limit, pause until reset${RESET}" }
}
$sd = $d.rate_limits.seven_day
if ($null -ne $sd.used_percentage) {
  $p = [int][math]::Round([double]$sd.used_percentage)
  if ($limits) { $limits += " ${DIM}·${RESET} " }
  $limits += "7d $(LimColor $p)${p}%${RESET}"
  if ($sd.resets_at) { $limits += " ${DIM}resets $(FmtTime $sd.resets_at 'ddd HH:mm')${RESET}" }
  if ($p -ge 90) { $limWarn = " ${RED}⚠ near limit, pause until reset${RESET}" }
}
$limits += $limWarn

$out = ''
if ($repo) { $out = "${BOLD}${YELLOW}${repo}${RESET}" }
if ($branch) { if ($out) { $out += ' ' }; $out += "${BOLD}${CYAN}🌿 (${branch})${RESET}" }
if ($out) { $out += " ${DIM}|${RESET} " }
$out += $ctxPart
$out += " ${DIM}|${RESET} ${costPart}"
$out += " ${DIM}|${RESET} ${velocity}"
if ($limits) { $out += " ${DIM}|${RESET} ⏱ ${limits}" }
$out += " ${DIM}|${RESET} ${MAGENTA}🤖 ${model}${RESET}"

[Console]::Out.Write($out)
