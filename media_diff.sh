#!/usr/bin/env bash
# Compare Radarr, Plex, and local movie directories by IMDb ID (optimized)

RADARR_URL="http://<IP>:7878"
RADARR_API_KEY="<api_key>"

PLEX_URL="http://<IP>:32400"
PLEX_TOKEN="<token>"
SECTION_KEY="<movie_section_id_plex>"

MOVIE_DIR="<local_dir_where_movies_are>"

# --- Check dependencies ---
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed."; exit 1; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint is required but not installed."; exit 1; }

# --- Step 1: Fetch Radarr movie list ---
echo "Fetching IMDb IDs from Radarr..."
radarr_json=$(curl -s "${RADARR_URL}/api/v3/movie" -H "X-Api-Key: ${RADARR_API_KEY}")
declare -A radarr_lookup
declare -A radarr_titles
while IFS=$'\t' read -r imdb_id title; do
    radarr_lookup["$imdb_id"]=1
    radarr_titles["$imdb_id"]="$title"
done < <(echo "$radarr_json" | jq -r '.[] | select(.imdbId != null) | "\(.imdbId)\t\(.title)"')

# --- Step 2: Fetch Plex movie list ---
echo "Fetching IMDb IDs from Plex..."
declare -A plex_lookup
while IFS= read -r line; do
    plex_lookup["$line"]=1
done < <(
    curl -s -H "X-Plex-Token: $PLEX_TOKEN" "$PLEX_URL/library/sections/$SECTION_KEY/all" \
      | xmllint --xpath '//Part/@file' - 2>/dev/null \
      | sed -E 's/file="([^"]+)"/\1\n/g' \
      | while read -r filepath; do
          [[ $filepath =~ imdb-(tt[0-9]+) ]] && echo "${BASH_REMATCH[1]}"
      done
)

# --- Step 3: Scan local disk ---
echo "Scanning local disk for IMDb IDs..."
declare -A disk_lookup
declare -A disk_paths
while IFS= read -r d; do
    if [[ $d =~ imdb-(tt[0-9]+) ]]; then
        id="${BASH_REMATCH[1]}"
        disk_lookup["$id"]=1
        disk_paths["$id"]="$d"
    fi
done < <(find "$MOVIE_DIR" -mindepth 1 -maxdepth 1 -type d)

# --- Step 4: Compare disk vs Radarr ---
echo
echo "Disk vs Radarr:"
missing_radarr=()
for id in "${!disk_lookup[@]}"; do
    if [ -z "${radarr_lookup[$id]}" ]; then
        missing_radarr+=("$id")
    fi
done

if [ ${#missing_radarr[@]} -eq 0 ]; then
    echo "Local disk is in sync with Radarr."
else
    for id in "${missing_radarr[@]}"; do
        echo "$id - ${disk_paths[$id]}"
    done
fi

# --- Step 5: Compare disk vs Plex ---
echo
echo "Disk vs Plex:"
missing_plex=()
for id in "${!disk_lookup[@]}"; do
    if [ -z "${plex_lookup[$id]}" ]; then
        missing_plex+=("$id")
    fi
done

if [ ${#missing_plex[@]} -eq 0 ]; then
    echo "Local disk is in sync with Plex."
else
    for id in "${missing_plex[@]}"; do
        echo "$id - ${disk_paths[$id]}"
    done
fi
