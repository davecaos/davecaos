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

# Build bar segments (no gaps — seamless)
BAR_SEGMENTS=""
X_OFFSET=0
BAR_Y=80
BAR_H=8

while IFS=$'\t' read -r _ color bytes; do
  width=$(awk "BEGIN{printf \"%.2f\", ($bytes/$TOTAL_BYTES)*540}")
  BAR_SEGMENTS="$BAR_SEGMENTS"'<rect x="'"$X_OFFSET"'" y="'"$BAR_Y"'" width="'"$width"'" height="'"$BAR_H"'" fill="'"$color"'"/>'
  X_OFFSET=$(awk "BEGIN{printf \"%.2f\", $X_OFFSET + $width}")
done <<< "$LANG_DATA"

# Build 2-column legend
LEGEND_ITEMS=""
LEGEND_Y=116
LEGEND_COL=0
LEGEND_ROW=0
ITEMS_PER_COL=4
COL_WIDTH=270

while IFS=$'\t' read -r name color bytes; do
  pct=$(awk "BEGIN{printf \"%.1f\", ($bytes/$TOTAL_BYTES)*100}")
  LX=$((30 + LEGEND_COL * COL_WIDTH))
  LY=$((LEGEND_Y + LEGEND_ROW * 30))

  LEGEND_ITEMS="$LEGEND_ITEMS"'
    <circle cx="'"$LX"'" cy="'"$LY"'" r="4" fill="'"$color"'"/>
    <text x="'"$((LX + 14))"'" y="'"$((LY + 4))"'" fill="#ededed" font-size="13" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif" font-weight="400">'"$name"'</text>
    <text x="'"$((LX + COL_WIDTH - 40))"'" y="'"$((LY + 4))"'" fill="#666" font-size="12" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif" text-anchor="end">'"$pct"'%</text>'

  LEGEND_ROW=$((LEGEND_ROW + 1))
  if [ "$LEGEND_ROW" -ge "$ITEMS_PER_COL" ]; then
    LEGEND_ROW=0
    LEGEND_COL=$((LEGEND_COL + 1))
  fi
done <<< "$LANG_DATA"

SVG_HEIGHT=$((LEGEND_Y + ITEMS_PER_COL * 30 + 16))

cat > "$STATS_DIR/top-langs.svg" <<SVGEOF
<svg width="600" height="$SVG_HEIGHT" xmlns="http://www.w3.org/2000/svg">
  <rect width="600" height="$SVG_HEIGHT" rx="8" fill="#000"/>
  <rect x="0.5" y="0.5" width="599" height="$((SVG_HEIGHT - 1))" rx="8" fill="none" stroke="#333" stroke-width="1"/>
  <text x="30" y="40" fill="#fff" font-size="15" font-weight="600" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif" letter-spacing="0.3">Most Used Languages</text>
  <text x="30" y="60" fill="#666" font-size="12" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif">Aggregated across all repositories</text>
  <clipPath id="bar-clip"><rect x="30" y="$BAR_Y" width="540" height="$BAR_H" rx="4"/></clipPath>
  <g clip-path="url(#bar-clip)">
    <rect x="30" y="$BAR_Y" width="540" height="$BAR_H" rx="4" fill="#1a1a1a"/>
    $BAR_SEGMENTS
  </g>
  <line x1="30" y1="100" x2="570" y2="100" stroke="#222" stroke-width="1"/>
  $LEGEND_ITEMS
</svg>
SVGEOF

echo "Generated $STATS_DIR/top-langs.svg"

# ── Top Repos SVG ─────────────────────────────────────────────────────────
REPO_DATA=$(echo "$DATA" | jq -r '
  [.data.user.repositories.nodes[] | select(.stargazerCount > 0)] |
  sort_by(-.stargazerCount) | .[0:5] | .[] |
  "\(.name)\t\(.stargazerCount)\t\(.forkCount)\t\(.primaryLanguage.name // "—")\t\(.primaryLanguage.color // "#666")"
')

REPO_SVG_ITEMS=""
ROW=0
TOTAL_REPOS=$(echo "$REPO_DATA" | wc -l | tr -d ' ')

while IFS=$'\t' read -r name stars forks lang lang_color; do
  ROW_Y=$((78 + ROW * 56))

  # Repo name
  REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <text x="30" y="'"$ROW_Y"'" fill="#ededed" font-size="14" font-weight="500" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif">'"$name"'</text>'

  # Metadata row
  META_Y=$((ROW_Y + 20))

  # Language dot + name
  REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <circle cx="34" cy="'"$((META_Y - 4))"'" r="4" fill="'"$lang_color"'"/>
    <text x="44" y="'"$META_Y"'" fill="#666" font-size="12" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif">'"$lang"'</text>'

  # Stars
  REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <text x="120" y="'"$META_Y"'" fill="#666" font-size="12" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif">&#9733; '"$stars"'</text>'

  # Forks (only if > 0)
  if [ "$forks" -gt 0 ]; then
    REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <text x="170" y="'"$META_Y"'" fill="#666" font-size="12" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif">&#9741; '"$forks"'</text>'
  fi

  # Separator line (not after last)
  if [ "$ROW" -lt "$((TOTAL_REPOS - 1))" ]; then
    SEP_Y=$((META_Y + 14))
    REPO_SVG_ITEMS="$REPO_SVG_ITEMS"'
    <line x1="30" y1="'"$SEP_Y"'" x2="570" y2="'"$SEP_Y"'" stroke="#222" stroke-width="1"/>'
  fi

  ROW=$((ROW + 1))
done <<< "$REPO_DATA"

REPO_SVG_HEIGHT=$((78 + ROW * 56 + 4))

cat > "$STATS_DIR/top-repos.svg" <<SVGEOF
<svg width="600" height="$REPO_SVG_HEIGHT" xmlns="http://www.w3.org/2000/svg">
  <rect width="600" height="$REPO_SVG_HEIGHT" rx="8" fill="#000"/>
  <rect x="0.5" y="0.5" width="599" height="$((REPO_SVG_HEIGHT - 1))" rx="8" fill="none" stroke="#333" stroke-width="1"/>
  <text x="30" y="40" fill="#fff" font-size="15" font-weight="600" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif" letter-spacing="0.3">Top Contributed Repos</text>
  <text x="30" y="60" fill="#666" font-size="12" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif">Sorted by stargazer count</text>
  <line x1="30" y1="66" x2="570" y2="66" stroke="#222" stroke-width="1"/>
  $REPO_SVG_ITEMS
</svg>
SVGEOF

echo "Generated $STATS_DIR/top-repos.svg"
echo "Done! Commit and push to update your profile."
