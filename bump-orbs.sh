# CIRCLECI_CLI_TOKEN is required for the orb refresh to find private orbs.
# CIRCLECI_CONFIG_FILE is required to specify the configuration file to use.

GITHUB_OUTPUT=${GITHUB_OUTPUT-output}
ORBS="./orbs"
STANZA='/^orbs:/,/^[^ ][^ ]/' # stanza to match initial orbs section of the config

trap "rm -fr ${ORBS}" 1 2 3 6

CONFIG="$1"
if [ "$#" -gt 1 ]; then
    export CIRCLECI_CLI_TOKEN="$2"
fi

NAMESPACES="$(sed -n "${STANZA}s!/!&!p" "$CONFIG" | cut -f2 -d: | cut -f1 -d/ | sort -u)"

for ns in $NAMESPACES; do
    circleci --skip-update-check orb list $ns --uncertified | sed -n 's/ (\([^)]*\))$/@\1/gp' \
        | grep -v "Not published" >> $ORBS
    if [ -z "$CIRCLECI_CLI_TOKEN" ]; then
        echo "$ns: CIRCLECI_CLI_TOKEN must be set to retrieve private orbs" >>$GITHUB_OUTPUT
        break
    else
        circleci --skip-update-check orb list --uncertified --private "$ns" 2>/dev/null \
            | sed -n 's/ (\([^)]*\))$/@\1/gp' | grep -v "Not published" >> $ORBS || \
            echo "Failed to retrieve private orbs for $ns" >>$GITHUB_OUTPUT
    fi
done

if [ ! -f "$ORBS" ]; then
    echo "Failed to retrieve any latest versions"
    rm -fr "$ORBS"
    exit 1
fi

sed -n "${STANZA}{/^  *[^:]*: *[^ ]\+@[^ ]\+/p}" "$CONFIG" \
    | cut -f 2 -d ':' \
    | while read line; do
    orb=$(echo $line | cut -f 1 -d'@')
    version=$(echo $line | cut -f 2 -d'@')
    latest=$(grep "$orb" "$ORBS" | cut -f 2 -d'@')

    if [ -n "$latest" ]; then
        if [ "$version" != "$latest" ]; then
            sed -i "${STANZA}s!${orb}@${version}!${orb}@${latest}!g" "$CONFIG"
            echo "bumped $orb to $latest" >>$GITHUB_OUTPUT
        else
            echo "$orb is already at $latest" >>$GITHUB_OUTPUT
        fi
    fi
done

rm -fr "$ORBS"
