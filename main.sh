#!/bin/bash
set -euo pipefail

############################
# CONFIG
############################
LEVEL=3
THREADS=50
TIMEOUT=10
LINKFINDER_PATH="~/tools/LinkFinder/linkfinder.py"

############################
# INPUT CHECK
############################
if [ "$#" -eq 0 ]; then
  echo "Usage: ./auto.sh target.txt OR ./auto.sh example.com"
  exit 1
fi

############################
# WORKDIR SETUP
############################
BASE_DIR="$(pwd)"
WORKDIR="$BASE_DIR/recon_$(date +%s)"
mkdir -p "$WORKDIR"

############################
# SCOPE NORMALIZATION
############################
if [ -f "$1" ]; then
  echo "[+] Scope file detected"
  cp "$1" "$WORKDIR/scope.txt"
else
  echo "[+] Single domain detected"
  echo "$1" > "$WORKDIR/scope.txt"
fi

cd "$WORKDIR"

############################
# SUBDOMAIN ENUMERATION
############################
echo "[+] Subdomain enumeration started"
cp scope.txt level_0.txt

for ((i=0; i<LEVEL; i++)); do
  echo "[+] Subfinder level $i"
  subfinder -dL "level_${i}.txt" -silent -all -o "level_$((i+1)).raw"
  sort -u "level_$((i+1)).raw" > "level_$((i+1)).txt"

  if [ ! -s "level_$((i+1)).txt" ]; then
    echo "[-] No new subdomains at level $i"
    break
  fi
done

cat level_*.txt | sort -u > all_subdomains.txt
echo "[+] Total subdomains: $(wc -l < all_subdomains.txt)"

############################
# HTTP PROBING
############################
echo "[+] Running httpx"
httpx -l all_subdomains.txt \
  -silent \
  -status-code \
  -title \
  -tech-detect \
  -follow-redirects \
  -threads "$THREADS" \
  -timeout "$TIMEOUT" \
  -o alive_hosts.txt

awk 'match($0, /\[(2|3)[0-9]{2}\]/) {print $1}' alive_hosts.txt > live_2xx_3xx.txt
awk 'match($0, /\[4[0-9]{2}\]/) {print $1}' alive_hosts.txt > live_4xx.txt

############################
# URL DISCOVERY
############################
echo "[+] Crawling with Katana"
katana -list live_2xx_3xx.txt \
  -depth 4 \
  -js-crawl \
  -known-files all \
  -silent \
  -o katana_urls.txt

sort -u katana_urls.txt > urls.txt

############################
# MULTI-SOURCE JS COLLECTION
############################
echo "[+] Collecting JS files"

grep -iE "\.js($|\?)" urls.txt > js_from_katana.txt || true

httpx -l live_2xx_3xx.txt -silent -body \
| grep -oE '<script[^>]+src=["'\'']([^"'\'']+\.js[^"'\'']*)["'\'']' \
| sed -E 's/.*src=["'\'']([^"'\'']+).*/\1/' \
| sort -u > js_from_httpx.txt || true


if command -v waybackurls &>/dev/null; then
  waybackurls < live_2xx_3xx.txt | grep -i "\.js" > js_from_wayback.txt || true
fi

cat js_from_katana.txt js_from_httpx.txt js_from_wayback.txt 2>/dev/null \
  | sort -u > js_files.txt

############################
# JS ENDPOINT EXTRACTION
############################
echo "[+] Extracting JS endpoints"

> js_endpoints_raw.txt

while read -r js; do
  # Skip empty lines
  [ -z "$js" ] && continue

  # Use a temporary file for LinkFinder
  tmpfile=$(mktemp)

  # Download JS into temp file, skip if fails
  curl -sk --max-time 15 "$js" -o "$tmpfile" || { echo "[!] Failed: $js"; rm -f "$tmpfile"; continue; }

  # Run LinkFinder on downloaded JS
  python3 "$LINKFINDER_PATH" -i "$tmpfile" -o cli 2>/dev/null \
    | grep -Eo "(\/[a-zA-Z0-9_\/\-\.\?=&]+)" || true \
    >> js_endpoints_raw.txt

  # Clean up temp file
  rm -f "$tmpfile"

done < js_files.txt

# Deduplicate all endpoints
sort -u js_endpoints_raw.txt > js_endpoints.txt

echo "[+] JS endpoint extraction completed: $(wc -l < js_endpoints.txt) endpoints found"


############################
# PARAM & PATH MINING
############################
grep "=" urls.txt js_endpoints.txt > params.txt || true

grep -iE "id=|uid=|user=|account=" params.txt > idor_candidates.txt || true
grep -iE "redirect=|url=|next=" params.txt > open_redirect.txt || true
grep -iE "file=|path=|download=" params.txt > lfi_candidates.txt || true

grep -iE "/api|/v1|/v2|/v3" urls.txt js_endpoints.txt > api_urls.txt || true
grep -iE "/admin|/internal|/debug|/test|/staging|/dev" urls.txt js_endpoints.txt \
  > hidden_paths.txt || true

############################
# CONDITIONAL FLAGS
############################
RUN_PARAM=false
RUN_API=false
RUN_JS=false
RUN_AUTH=false

[ -s params.txt ] && RUN_PARAM=true
[ -s api_urls.txt ] && RUN_API=true
[ -s js_files.txt ] && RUN_JS=true

grep -iE "login|signin|signup|auth|reset|forgot" urls.txt js_endpoints.txt \
  > auth_pages.txt || true
[ -s auth_pages.txt ] && RUN_AUTH=true

############################
# SMART NUCLEI
############################
echo "[+] Running conditional nuclei"

$RUN_AUTH && nuclei -l live_2xx_3xx.txt -tags auth,session,oauth \
  -severity medium,high,critical -rate-limit 100 -o nuclei_auth.txt

$RUN_API && nuclei -l api_urls.txt -tags api,idor,graphql,swagger \
  -severity medium,high,critical -rate-limit 100 -o nuclei_api.txt

$RUN_PARAM && nuclei -l live_2xx_3xx.txt -tags idor,xss,lfi,sqli,ssrf \
  -severity high,critical -rate-limit 80 -o nuclei_params.txt

$RUN_JS && nuclei -l live_2xx_3xx.txt -tags exposure,misconfig,debug \
  -severity medium,high -rate-limit 100 -o nuclei_js.txt

cat nuclei_*.txt 2>/dev/null | sort -u > nuclei_final.txt

############################
# SUMMARY
############################
echo "[+] Recon completed"
echo "[+] Subdomains     : $(wc -l < all_subdomains.txt)"
echo "[+] URLs           : $(wc -l < urls.txt)"
echo "[+] JS files       : $(wc -l < js_files.txt)"
echo "[+] JS endpoints   : $(wc -l < js_endpoints.txt)"
echo "[+] API endpoints  : $(wc -l < api_urls.txt)"
echo "[+] Findings       : $(wc -l < nuclei_final.txt)"
echo "[+] Output dir     : $WORKDIR"
