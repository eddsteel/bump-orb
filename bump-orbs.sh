#!/usr/bin/env bash
# CIRCLECI_CLI_TOKEN is required for the orb refresh to find private orbs.
# CIRCLECI_CONFIG_FILE is required to specify the configuration file to use.

GITHUB_OUTPUT=${GITHUB_OUTPUT-output}
GITHUB_STEP_SUMMARY=${GITHUB_STEP_SUMMARY-steps.md}
ORBS="./orbs"
STANZA='/^orbs:/,/^[^ ][^ ]/' # stanza to match initial orbs section of the config

trap "rm -fr ${ORBS}" 1 2 3 6

CONFIG="$1"
if [ "$#" -gt 1 ]; then
    export CIRCLECI_CLI_TOKEN="$2"
fi

if ! grep -q '^orbs:' "$CONFIG"; then
    echo "Orbs are not used." >> $GITHUB_STEP_SUMMARY
    echo "summary=Orbs are not used." >> $GITHUB_OUTPUT
    exit 0
fi

NAMESPACES="$(sed -n "${STANZA}s!/!&!p" "$CONFIG" | cut -f2 -d: | cut -f1 -d/ | sort -u)"

for ns in $NAMESPACES; do
    circleci --skip-update-check orb list $ns --uncertified | sed -n 's/ (\([^)]*\))$/@\1/gp' \
        | grep -v "Not published" >> $ORBS
    if [ -z "$CIRCLECI_CLI_TOKEN" ]; then
        echo "$ns: CIRCLECI_CLI_TOKEN must be set to retrieve private orbs"
        break
    else
        circleci --skip-update-check orb list --uncertified --private "$ns" 2>/dev/null \
            | sed -n 's/ (\([^)]*\))$/@\1/gp' | grep -v "Not published" >> $ORBS || \
            echo "Failed to retrieve private orbs for $ns"
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
            echo "- bumped \`$orb\` to $latest (was $version)" >> out-updates
        else
            echo "- \`$orb\` is already at $latest" >> out-latest
        fi
    fi
done


if [ -s out-updates ]; then
    echo "### Updates" >> $GITHUB_STEP_SUMMARY
    cat out-updates >> $GITHUB_STEP_SUMMARY
fi

if [ -s out-latest ]; then
    echo "### Already up to date" >> $GITHUB_STEP_SUMMARY
    cat out-latest >> $GITHUB_STEP_SUMMARY
fi

if [ -s out-updates ]; then
    output=$(cat out-updates)
    output="${output//'%'/'%25'}"
    output="${output//$'\n'/'%0A'}"
    output="${output//$'\r'/'%0D'}"
    echo "summary=${output}" >> $GITHUB_OUTPUT
else
    echo "summary=No changes." >> $GITHUB_OUTPUT
fi

rm -fr "$ORBS"
rm -fr out-latest
rm -fr out-updates
