#!/bin/bash

set -euo pipefail

DEPTH=3   # 1 base + 2 deeper levels
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
SCOPE_FILE="$WORKDIR/scope_level_1.txt"

# -----------------------------
# Normalize initial scope
# -----------------------------
if [ -f "$INPUT" ]; then
  if [ ! -r "$INPUT" ]; then
    echo "[-] Cannot read scope file"
    exit 1
  fi
  grep -vE '^\s*#|^\s*$' "$INPUT" | sort -u > "$SCOPE_FILE"
else
  echo "$INPUT" > "$SCOPE_FILE"
fi

echo "[+] Initial scope prepared"

# -----------------------------
# Recursive Enumeration
# -----------------------------
for LEVEL in $(seq 1 "$DEPTH"); do
  echo "[+] Enumeration Level $LEVEL started"

  LEVEL_DIR="$WORKDIR/level_$LEVEL"
  mkdir -p "$LEVEL_DIR"

  SUB_OUT="$LEVEL_DIR/subfinder.txt"
  MERGED_OUT="$LEVEL_DIR/all_subdomains.txt"

  echo "[*] Running Subfinder..."
  subfinder -dL "$SCOPE_FILE" -silent | sort -u > "$SUB_OUT"

  COUNT=$(wc -l < "$SUB_OUT")
  echo "[+] Level $LEVEL found $COUNT subdomains"

  if [ "$COUNT" -eq 0 ]; then
    echo "[!] No results found, stopping recursion"
    break
  fi

  cp "$SUB_OUT" "$MERGED_OUT"

  # Prepare scope for next level
  if [ "$LEVEL" -lt "$DEPTH" ]; then
    NEXT_SCOPE="$WORKDIR/scope_level_$((LEVEL + 1)).txt"

    awk -F. '
      NF > 2 {
        print $(NF-1)"."$NF
      }
    ' "$MERGED_OUT" | sort -u > "$NEXT_SCOPE"

    if [ ! -s "$NEXT_SCOPE" ]; then
      echo "[!] No new parent domains for next level"
      break
    fi

    SCOPE_FILE="$NEXT_SCOPE"
  fi
done

# -----------------------------
# Final Merge
# -----------------------------
echo "[+] Merging all levels..."

find "$WORKDIR" -name "all_subdomains.txt" -exec cat {} \; \
  | sort -u > "$WORKDIR/final_subdomains.txt"

TOTAL=$(wc -l < "$WORKDIR/final_subdomains.txt")

echo "[+] Recon completed"
echo "[+] Total unique subdomains found: $TOTAL"
echo "[+] Final output: $WORKDIR/final_subdomains.txt"
