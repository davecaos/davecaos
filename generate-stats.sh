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
# Aggregate bytes per language across all repos
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

# Build the bar segments and legend
BAR_SEGMENTS=""
LEGEND_ITEMS=""
X_OFFSET=0
LEGEND_Y=110
LEGEND_COL=0
LEGEND_ROW=0
ITEMS_PER_ROW=4

while IFS=$'\t' read -r name color bytes; do
  pct=$(awk "BEGIN{printf \"%.1f\", ($bytes/$TOTAL_BYTES)*100}")
  width=$(awk "BEGIN{printf \"%.2f\", ($bytes/$TOTAL_BYTES)*370}")

  BAR_SEGMENTS="$BAR_SEGMENTS"'<rect x="'"$X_OFFSET"'" y="70" width="'"$width"'" height="25" rx="0" fill="'"$color"'"/>'
  X_OFFSET=$(awk "BEGIN{printf \"%.2f\", $X_OFFSET + $width}")

  # Legend position
  LX=$((25 + LEGEND_COL * 95))
  LY=$((LEGEND_Y + LEGEND_ROW * 22))
  LEGEND_ITEMS="$LEGEND_ITEMS"'
    <circle cx="'"$LX"'" cy="'"$LY"'" r="5" fill="'"$color"'"/>
    <text x="'"$((LX + 10))"'" y="'"$((LY + 4))"'" fill="#c9d1d9" font-size="11" font-family="Segoe UI, Helvetica, Arial, sans-serif">'"$name"' '"$pct"'%</text>'

  LEGEND_COL=$((LEGEND_COL + 1))
  if [ "$LEGEND_COL" -ge "$ITEMS_PER_ROW" ]; then
    LEGEND_COL=0
    LEGEND_ROW=$((LEGEND_ROW + 1))
  fi
done <<< "$LANG_DATA"

# Use clipPath for rounded corners instead of per-segment rounding

SVG_HEIGHT=$((LEGEND_Y + (LEGEND_ROW + 1) * 22 + 10))

cat > "$STATS_DIR/top-langs.svg" <<SVGEOF
<svg width="420" height="$SVG_HEIGHT" xmlns="http://www.w3.org/2000/svg">
  <rect width="420" height="$SVG_HEIGHT" rx="10" fill="#0d1117" stroke="#30363d" stroke-width="1"/>
  <text x="25" y="35" fill="#c9d1d9" font-size="16" font-weight="600" font-family="Segoe UI, Helvetica, Arial, sans-serif">Most Used Languages</text>
  <clipPath id="bar-clip"><rect x="25" y="70" width="370" height="25" rx="5"/></clipPath>
  <g clip-path="url(#bar-clip)">
    $BAR_SEGMENTS
  </g>
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
  Y=$((65 + ROW * 50))
  REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <text x="25" y="'"$Y"'" fill="#58a6ff" font-size="14" font-weight="600" font-family="Segoe UI, Helvetica, Arial, sans-serif">'"$name"'</text>
    <circle cx="25" cy="'"$((Y + 18))"'" r="5" fill="'"$lang_color"'"/>
    <text x="35" y="'"$((Y + 22))"'" fill="#8b949e" font-size="11" font-family="Segoe UI, Helvetica, Arial, sans-serif">'"$lang"'</text>
    <text x="140" y="'"$((Y + 22))"'" fill="#8b949e" font-size="11" font-family="Segoe UI, Helvetica, Arial, sans-serif">&#9733; '"$stars"'</text>
    <text x="190" y="'"$((Y + 22))"'" fill="#8b949e" font-size="11" font-family="Segoe UI, Helvetica, Arial, sans-serif">&#9741; '"$forks"'</text>'
  ROW=$((ROW + 1))
done <<< "$REPO_DATA"

REPO_SVG_HEIGHT=$((65 + ROW * 50 + 15))

cat > "$STATS_DIR/top-repos.svg" <<SVGEOF
<svg width="420" height="$REPO_SVG_HEIGHT" xmlns="http://www.w3.org/2000/svg">
  <rect width="420" height="$REPO_SVG_HEIGHT" rx="10" fill="#0d1117" stroke="#30363d" stroke-width="1"/>
  <text x="25" y="35" fill="#c9d1d9" font-size="16" font-weight="600" font-family="Segoe UI, Helvetica, Arial, sans-serif">Top Contributed Repos</text>
  $REPO_SVG_ITEMS
</svg>
SVGEOF

echo "Generated $STATS_DIR/top-repos.svg"
echo "Done! Commit and push to update your profile."
