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
    echo "Subfinder Started"
    LEVEL=4
    for LOOP in $(seq 0 "$LEVEL"); do
    echo "Level $LOOP begins"
    INPUTS=("$FILE" 'subfinder_level1' 'subfinder_level2' 'subfinder_level3' 'subfinder_level4' 'subfinder_level5')
    OUTPUTS=('subfinder_level1' 'subfinder_level2' 'subfinder_level3' 'subfinder_level4' 'subfinder_level5');
    FILE="$1"
    subfinder -dL "${INPUTS[$LOOP]}" -silent -o "${OUTPUTS[$LOOP]}"
    echo "Subfinder Completed!"
    if [ ! -s "${INPUTS[$LOOP]}" ]; then
      echo "No results found, stopping enumeration"
      break
    fi
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



