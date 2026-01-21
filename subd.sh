#!/bin/bash

set -euo pipefail

DEPTH=3   # total levels (1 base + 2 deeper)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
WORKDIR="recon_$TIMESTAMP"

mkdir -p "$WORKDIR"

# -----------------------------
# Input validation
# -----------------------------
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <domain | scope_file>"
  exit 1
fi

INPUT="$1"
SCOPE_FILE="$WORKDIR/scope.txt"

# -----------------------------
# Normalize initial scope
# -----------------------------
if [ -f "$INPUT" ]; then
  if [ ! -r "$INPUT" ]; then
    echo "[-] Cannot read scope file"
    exit 1
  fi
  grep -vE '^\s*#|^\s*$' "$INPUT" > "$SCOPE_FILE"
else
  echo "$INPUT" > "$SCOPE_FILE"
fi

# -----------------------------
# Enumeration Loop
# -----------------------------
for LEVEL in $(seq 1 "$DEPTH"); do
  echo "[+] Enumeration Level $LEVEL started"

  LEVEL_DIR="$WORKDIR/level_$LEVEL"
  mkdir -p "$LEVEL_DIR"

  SUBFINDER_OUT="$LEVEL_DIR/subfinder.txt"
  AMASS_OUT="$LEVEL_DIR/amass.txt"
  MERGED_OUT="$LEVEL_DIR/all_subdomains.txt"

  echo "[*] Subfinder running..."
  subfinder -dL "$SCOPE_FILE" -silent -o "$SUBFINDER_OUT"

  echo "[*] Amass running..."
  amass enum -passive -df "$SCOPE_FILE" -o "$AMASS_OUT"

  cat "$SUBFINDER_OUT" "$AMASS_OUT" | sort -u > "$MERGED_OUT"

  COUNT=$(wc -l < "$MERGED_OUT")
  echo "[+] Level $LEVEL found $COUNT subdomains"

  # Stop if nothing new is found
  if [ "$COUNT" -eq 0 ]; then
    echo "[!] No new subdomains found, stopping recursion"
    break
  fi

  # Prepare scope for next level
  if [ "$LEVEL" -lt "$DEPTH" ]; then
    NEXT_SCOPE="$WORKDIR/scope_level_$((LEVEL + 1)).txt"

    # Extract parent domains safely
    awk -F. '{ 
      if (NF > 2) {
        print $(NF-1)"."$NF
      }
    }' "$MERGED_OUT" | sort -u > "$NEXT_SCOPE"

    SCOPE_FILE="$NEXT_SCOPE"
  fi
done

# -----------------------------
# Final merge
# -----------------------------
echo "[+] Merging all levels..."

find "$WORKDIR" -name "all_subdomains.txt" -exec cat {} \; \
  | sort -u > "$WORKDIR/final_subdomains.txt"

TOTAL=$(wc -l < "$WORKDIR/final_subdomains.txt")

echo "[+] Recon completed"
echo "[+] Total unique subdomains found: $TOTAL"
echo "[+] Final output: $WORKDIR/final_subdomains.txt
