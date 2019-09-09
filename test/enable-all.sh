#!/bin/bash
for i in *.disable; do
    RENAMED=$(echo $i | sed 's/disable$/test/')
    echo "$i -> $RENAMED"
    mv "$i" "$RENAMED"
done
