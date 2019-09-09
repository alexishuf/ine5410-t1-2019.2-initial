#!/bin/bash
for i in *.test; do
    RENAMED=$(echo $i | sed 's/test$/disable/')
    echo "$i -> $RENAMED"
    mv "$i" "$RENAMED"
done
