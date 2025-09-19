#!/bin/bash
set -e

# Arguments
source_file="$1"
target_file="$2"
pages_tsv="$3"

# Configuration
MARKDOWN=smu

# Extract information
title=$(sed -n '/^# /{s/# //p; q}' "$source_file")
created=$(grep "$source_file	" "$pages_tsv" | cut -f3 | sed 's/T.*//')
updated=$(grep "$source_file	" "$pages_tsv" | cut -f4 | sed 's/T.*//')

# Generate content
content=$($MARKDOWN "$source_file")

# Add timestamp if not draft
if [ "$created" != "draft" ] && [ "$updated" != "draft" ]; then
    if [ "$created" != "$updated" ]; then
        dates_text="<small>Last updated on $updated.</small>"
    else
        dates_text="<small>Created on $created.</small>"
    fi
else
    dates_text=""
fi

# Generate final HTML
{
    cat header.html
    echo "$content"
    echo "$dates_text"
} | sed "s/{{TITLE}}/$title/" > "$target_file"

echo "Generated: $target_file"
