#!/bin/sh

CIDR_URL="https://raw.githubusercontent.com/touhidurrr/iplist-youtube/refs/heads/main/lists/cidr4.txt"

NFT_FAMILY="inet"
NFT_TABLE="fw4"
NFT_SET="youtube_domains"

echo "Downloading CIDR list from $CIDR_URL..."
CIDR_CONTENT=$(curl -sSL "$CIDR_URL")
CURL_EXIT_CODE=$?

if [ "$CURL_EXIT_CODE" -ne 0 ]; then
  echo "Error: curl failed to download from $CIDR_URL (exit code: $CURL_EXIT_CODE)."
  exit 1
fi

if [ -z "$CIDR_CONTENT" ]; then
  echo "Error: Downloaded CIDR list from $CIDR_URL is empty."
  exit 1
fi

total_lines=$(echo "$CIDR_CONTENT" | wc -l | awk '{print $1}')

if ! [[ "$total_lines" =~ ^[0-9]+$ ]] || [ "$total_lines" -le 0 ]; then
    echo "Error: Could not count lines or downloaded content seems effectively empty (total_lines: $total_lines)."
    exit 1
fi

ELEMENTS_STRING=$(echo "$CIDR_CONTENT" | awk -v total="$total_lines" '{
  # $0 CIDR
  printf "%s", $0;
  if (NR < total) {
    printf ", ";
  }
}')

echo "Adding elements to nft set: $NFT_FAMILY/$NFT_TABLE/$NFT_SET..."
nft add element "$NFT_FAMILY" "$NFT_TABLE" "$NFT_SET" "{ $ELEMENTS_STRING }"
NFT_EXIT_CODE=$?

if [ "$NFT_EXIT_CODE" -ne 0 ]; then
  echo "Error: nft add element command failed (exit code: $NFT_EXIT_CODE)."
  exit 1
fi

echo "Elements added successfully."
