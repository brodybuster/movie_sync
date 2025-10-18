#!/usr/bin/env bash
# Compare Radarr, Plex, and local movie directories by IMDb ID

RADARR_URL="http://<IP>:7878"
RADARR_API_KEY="<api_key>"

PLEX_URL="http://<IP>:32400"
PLEX_TOKEN="<token>"
SECTION_KEY="<movie_section_id_plex>"

MOVIE_DIR="<local_dir_where_movies_are>"

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed."; exit 1; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint is required but not installed."; exit 1; }

# Fetch Radarr movie list
echo "Fetching IMDb IDs from Radarr..."
declare -A radarr_lookup
while IFS=$'\t' read -r imdb_id _; do
    radarr_lookup["$imdb_id"]=1
done < <(
    curl -s "${RADARR_URL}/api/v3/movie" -H "X-Api-Key: ${RADARR_API_KEY}" |
    jq -r '.[] | select(.imdbId != null) | "\(.imdbId)\t\(.title)"'
)

# Fetch Plex movie list
echo "Fetching IMDb IDs from Plex..."
declare -A plex_lookup
while IFS= read -r id; do
    plex_lookup["$id"]=1
done < <(
    curl -s -H "X-Plex-Token: $PLEX_TOKEN" "$PLEX_URL/library/sections/$SECTION_KEY/all" |
    xmllint --xpath '//Part/@file' - 2>/dev/null |
    sed -E 's/file="([^"]+)"/\1\n/g' |
    while read -r filepath; do
        [[ $filepath =~ imdb-(tt[0-9]+) ]] && echo "${BASH_REMATCH[1]}"
    done |
    sort -u
)

# Scan local disk
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

# Compare disk vs Radarr
echo
echo "Disk vs Radarr:"
missing_radarr=()
for id in "${!disk_lookup[@]}"; do
    [[ -z "${radarr_lookup[$id]}" ]] && missing_radarr+=("$id")
done

if (( ${#missing_radarr[@]} == 0 )); then
    echo "Local disk is in sync with Radarr."
else
    for id in "${missing_radarr[@]}"; do
        echo "$id - ${disk_paths[$id]}"
    done
fi

# Compare disk vs Plex
echo
echo "Disk vs Plex:"
missing_plex=()
for id in "${!disk_lookup[@]}"; do
    [[ -z "${plex_lookup[$id]}" ]] && missing_plex+=("$id")
done

if (( ${#missing_plex[@]} == 0 )); then
    echo "Local disk is in sync with Plex."
else
    for id in "${missing_plex[@]}"; do
        echo "$id - ${disk_paths[$id]}"
    done
fi
