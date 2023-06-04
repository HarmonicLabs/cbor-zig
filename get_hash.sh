#!/bin/bash

if [ -z "$1" ]; then
    echo "usage: $0 /path/to/module"
    exit 1
fi

TMP="hash.tmp"
TMP2="hashes.tmp"
FOLDER="$1"
FLEN=${#FOLDER}

HASHES=""

for p in $(find $FOLDER -type f -print | LC_ALL=C sort); do
    # Get correct file name
    ILEN=${#p}
    LEN=$((ILEN - FLEN - 1))
    file=${p: -LEN}
    
    # Prepare content to be hashed
    echo -n "$file" > $TMP 
    echo -n -e '\x00' >> $TMP
    if [[ -x "$p" ]]; then
        echo -n -e '\x01' >> $TMP
    else
        echo -n -e '\x00' >> $TMP
    fi
    cat $p >> $TMP

    # Hash content
    h=$(sha256sum $TMP | head -c 64)

    # Append hash
    HASHES="${HASHES}${h}"
    echo "${file}, ${h}"

    echo $HASHES | xxd -r -p > $TMP2
done

FINAL=$(sha256sum $TMP2)
rm $TMP $TMP2

echo "1220${FINAL:0:64}"
