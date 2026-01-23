#!/bin/bash

set -x

if [ "$#" -eq 0 ]; then
  echo "Scope not given, pass it as Eg: ./auto.sh target.txt (or) ./auto.sh example.com"
  exit 1

elif [ -f "$1" ]; then
  FILE="$1"

  if [ -r "$FILE" ]; then
    echo "TARGET HAS BEEN SET: $1"
    cat "$FILE"

    echo "Subdomain Enumeration begins"
    LEVEL=4

    INPUTS=("$FILE" subfinder_level1 subfinder_level2 subfinder_level3 subfinder_level4)
    OUTPUTS=(subfinder_level1 subfinder_level2 subfinder_level3 subfinder_level4 subfinder_level5)

    for LOOP in $(seq 0 "$LEVEL"); do
      echo "Level $LOOP begins"

      INPUT="${INPUTS[$LOOP]}"
      OUTPUT="${OUTPUTS[$LOOP]}"

      subfinder -dL "$INPUT" -silent -o "$OUTPUT"
      echo "Subfinder Completed!"

      # 1️⃣ Stop if output file is empty
      if [ ! -s "$OUTPUT" ]; then
        echo "No subdomains found at level $LOOP. Stopping."
        break
      fi

      # 2️⃣ Sort input & output
      sort -u "$INPUT" > prev.sorted
      sort -u "$OUTPUT" > curr.sorted

      # 3️⃣ Extract only new subdomains
      comm -13 prev.sorted curr.sorted > new_only.txt

      # 4️⃣ Stop if no unique subdomains found
      if [ ! -s new_only.txt ]; then
        echo "No new unique subdomains found at level $LOOP. Stopping."
        break
      fi

      # 5️⃣ Prepare next level input
      mv new_only.txt "${INPUTS[$((LOOP + 1))]}"

    done

  else
    echo "Couldn't read scope file - Permission Issue"
    exit 1
  fi
else 
  DOMAIN="$1"
  echo "Treat input as a single scope value"
  echo "TARGET HAS BEEN SET"
  echo "$1"
  echo "Subdomain Enumeration begins"
  echo "Subfinder Started"
  subfinder -d "$DOMAIN" -silent -o sub1
  echo "Subfinder Completed!"
  echo "Amass Started"
  amass enum -passive -d "$DOMAIN" -o amass
  echo "Amass Completed!"
fi
