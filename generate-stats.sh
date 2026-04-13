#!/usr/bin/env bash
# Generates GitHub profile stats SVGs using the GitHub CLI (gh).
# Usage: ./generate-stats.sh
# Requirements: gh (GitHub CLI) authenticated, jq, awk, sort

set -euo pipefail

USERNAME="davecaos"
STATS_DIR="$(cd "$(dirname "$0")" && pwd)/stats"
mkdir -p "$STATS_DIR"

# ── Fetch data via GraphQL ────────────────────────────────────────────────
DATA=$(gh api graphql -f query='
{
  user(login: "'"$USERNAME"'") {
    repositories(first: 100, ownerAffiliations: OWNER) {
      nodes {
        name
        stargazerCount
        forkCount
        primaryLanguage { name color }
        languages(first: 10, orderBy: {field: SIZE, direction: DESC}) {
          edges { size node { name color } }
        }
      }
    }
  }
}')

# ── Top Languages SVG ─────────────────────────────────────────────────────
LANG_DATA=$(echo "$DATA" | jq -r '
  [.data.user.repositories.nodes[].languages.edges[] |
    {name: .node.name, color: .node.color, size: .size}
  ] | group_by(.name) | map({
    name: .[0].name,
    color: .[0].color,
    total: (map(.size) | add)
  }) | sort_by(-.total) | .[0:8] | .[]
  | "\(.name)\t\(.color)\t\(.total)"
')

TOTAL_BYTES=$(echo "$LANG_DATA" | awk -F'\t' '{s+=$3} END{print s}')

# Build bar segments with 2px gaps
BAR_SEGMENTS=""
X_OFFSET=25
BAR_WIDTH=550
BAR_Y=75
BAR_H=14
IDX=0

while IFS=$'\t' read -r name color bytes; do
  width=$(awk "BEGIN{printf \"%.2f\", ($bytes/$TOTAL_BYTES)*$BAR_WIDTH}")
  # Add 2px gap between segments (not before first)
  if [ "$IDX" -gt 0 ]; then
    X_OFFSET=$(awk "BEGIN{printf \"%.2f\", $X_OFFSET + 2}")
  fi
  BAR_SEGMENTS="$BAR_SEGMENTS"'<rect x="'"$X_OFFSET"'" y="'"$BAR_Y"'" width="'"$width"'" height="'"$BAR_H"'" rx="3" fill="'"$color"'" opacity="0.9"/>'
  X_OFFSET=$(awk "BEGIN{printf \"%.2f\", $X_OFFSET + $width}")
  IDX=$((IDX + 1))
done <<< "$LANG_DATA"

# Build 2-column legend (4 per column, 275px each)
LEGEND_ITEMS=""
LEGEND_Y=115
LEGEND_COL=0
LEGEND_ROW=0
ITEMS_PER_COL=4
COL_WIDTH=275

while IFS=$'\t' read -r name color bytes; do
  pct=$(awk "BEGIN{printf \"%.1f\", ($bytes/$TOTAL_BYTES)*100}")

  LX=$((30 + LEGEND_COL * COL_WIDTH))
  LY=$((LEGEND_Y + LEGEND_ROW * 28))

  LEGEND_ITEMS="$LEGEND_ITEMS"'
    <circle cx="'"$LX"'" cy="'"$LY"'" r="6" fill="'"$color"'"/>
    <text x="'"$((LX + 14))"'" y="'"$((LY + 5))"'" fill="#c9d1d9" font-size="13" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-weight="500">'"$name"'</text>
    <text x="'"$((LX + COL_WIDTH - 40))"'" y="'"$((LY + 5))"'" fill="#8b949e" font-size="12" font-family="Segoe UI, Helvetica, Arial, sans-serif" text-anchor="end">'"$pct"'%</text>'

  LEGEND_ROW=$((LEGEND_ROW + 1))
  if [ "$LEGEND_ROW" -ge "$ITEMS_PER_COL" ]; then
    LEGEND_ROW=0
    LEGEND_COL=$((LEGEND_COL + 1))
  fi
done <<< "$LANG_DATA"

MAX_ROW=$ITEMS_PER_COL
SVG_HEIGHT=$((LEGEND_Y + MAX_ROW * 28 + 20))

cat > "$STATS_DIR/top-langs.svg" <<SVGEOF
<svg width="600" height="$SVG_HEIGHT" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg-grad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#0d1117"/>
      <stop offset="100%" stop-color="#161b22"/>
    </linearGradient>
    <filter id="card-shadow">
      <feDropShadow dx="0" dy="2" stdDeviation="6" flood-color="#000" flood-opacity="0.4"/>
    </filter>
  </defs>
  <rect width="600" height="$SVG_HEIGHT" rx="12" fill="url(#bg-grad)" stroke="#30363d" stroke-width="1" filter="url(#card-shadow)"/>
  <text x="30" y="38" fill="#e6edf3" font-size="18" font-weight="700" font-family="Segoe UI, Helvetica, Arial, sans-serif">Most Used Languages</text>
  <line x1="30" y1="50" x2="120" y2="50" stroke="#58a6ff" stroke-width="2" stroke-linecap="round" opacity="0.6"/>
  <rect x="25" y="$BAR_Y" width="550" height="$BAR_H" rx="7" fill="#21262d"/>
  $BAR_SEGMENTS
  $LEGEND_ITEMS
</svg>
SVGEOF

echo "Generated $STATS_DIR/top-langs.svg"

# ── Top Repos SVG ─────────────────────────────────────────────────────────
REPO_DATA=$(echo "$DATA" | jq -r '
  [.data.user.repositories.nodes[] | select(.stargazerCount > 0)] |
  sort_by(-.stargazerCount) | .[0:5] | .[] |
  "\(.name)\t\(.stargazerCount)\t\(.forkCount)\t\(.primaryLanguage.name // "—")\t\(.primaryLanguage.color // "#8b949e")"
')

REPO_SVG_ITEMS=""
ROW=0
while IFS=$'\t' read -r name stars forks lang lang_color; do
  ROW_Y=$((80 + ROW * 60))
  STRIPE_Y=$((ROW_Y - 15))

  # Alternating row background
  if [ $((ROW % 2)) -eq 0 ]; then
    REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <rect x="12" y="'"$STRIPE_Y"'" width="576" height="55" rx="6" fill="#161b22" opacity="0.5"/>'
  fi

  # Repo name
  REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <text x="30" y="'"$((ROW_Y + 4))"'" fill="#58a6ff" font-size="15" font-weight="700" font-family="Segoe UI, Helvetica, Arial, sans-serif">'"$name"'</text>'

  # Language pill
  PILL_X=30
  PILL_Y=$((ROW_Y + 16))
  REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <rect x="'"$PILL_X"'" y="'"$PILL_Y"'" width="70" height="18" rx="9" fill="'"$lang_color"'" opacity="0.25"/>
    <circle cx="'"$((PILL_X + 12))"'" cy="'"$((PILL_Y + 9))"'" r="4" fill="'"$lang_color"'"/>
    <text x="'"$((PILL_X + 21))"'" y="'"$((PILL_Y + 13))"'" fill="#c9d1d9" font-size="11" font-family="Segoe UI, Helvetica, Arial, sans-serif">'"$lang"'</text>'

  # Stars (golden)
  STAR_X=130
  REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <text x="'"$STAR_X"'" y="'"$((PILL_Y + 13))"'" fill="#e3b341" font-size="12" font-family="Segoe UI, Helvetica, Arial, sans-serif">&#9733; '"$stars"'</text>'

  # Forks
  FORK_X=185
  REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <text x="'"$FORK_X"'" y="'"$((PILL_Y + 13))"'" fill="#8b949e" font-size="12" font-family="Segoe UI, Helvetica, Arial, sans-serif">&#9741; '"$forks"'</text>'

  ROW=$((ROW + 1))
done <<< "$REPO_DATA"

REPO_SVG_HEIGHT=$((80 + ROW * 60 + 10))

cat > "$STATS_DIR/top-repos.svg" <<SVGEOF
<svg width="600" height="$REPO_SVG_HEIGHT" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg-grad2" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#0d1117"/>
      <stop offset="100%" stop-color="#161b22"/>
    </linearGradient>
    <filter id="card-shadow2">
      <feDropShadow dx="0" dy="2" stdDeviation="6" flood-color="#000" flood-opacity="0.4"/>
    </filter>
  </defs>
  <rect width="600" height="$REPO_SVG_HEIGHT" rx="12" fill="url(#bg-grad2)" stroke="#30363d" stroke-width="1" filter="url(#card-shadow2)"/>
  <text x="30" y="38" fill="#e6edf3" font-size="18" font-weight="700" font-family="Segoe UI, Helvetica, Arial, sans-serif">Top Contributed Repos</text>
  <line x1="30" y1="50" x2="130" y2="50" stroke="#58a6ff" stroke-width="2" stroke-linecap="round" opacity="0.6"/>
  $REPO_SVG_ITEMS
</svg>
SVGEOF

echo "Generated $STATS_DIR/top-repos.svg"
echo "Done! Commit and push to update your profile."
