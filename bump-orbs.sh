#!/usr/bin/env bash
# CIRCLECI_CLI_TOKEN is required for the orb refresh to find private orbs.
# CIRCLECI_CONFIG_FILE is required to specify the configuration file to use.

set -euo pipefail

[[ -z "${DEBUG:-}" ]] || set -x

TMPDIR="$(mktemp -d)"
GITHUB_OUTPUT="${GITHUB_OUTPUT-output}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY-steps.md}"
ORBS="$(mktemp "${TMPDIR}/orbs.XXXXXXXX")"
OUT_LATEST="$(mktemp "${TMPDIR}/out-latest.XXXXXXXX")"
OUT_UPDATES="$(mktemp "${TMPDIR}/out-updates.XXXXXXXX")"
STANZA='/^orbs:/,/^[^[:space:]][^[:space:]]/' # stanza to match initial orbs section of the config

on_exit() {
  rm -fr "${TMPDIR}"
}

trap on_exit EXIT

CONFIG="$1"

# Use 2nd argument as CIRCLECI_CLI_TOKEN if provided, otherwise use the environment variable if available
export CIRCLECI_CLI_TOKEN="${2:-${CIRCLECI_CLI_TOKEN:-}}"

# Use 3rd argument as IGNORED_ORBS if provided, it is a white space (newline and/or space) separated list of orbs
IGNORED_ORBS=()
mapfile -t ignored_orbs_lines <<< "${3:-}"
for ignored_orbs_line in "${ignored_orbs_lines[@]}"; do
  IFS=" " read -r -a _ignored_orbs <<< "${ignored_orbs_line:-}"
  IGNORED_ORBS+=("${_ignored_orbs[@]}")
done

if ! grep -q '^orbs:' "${CONFIG}"; then
    echo "Orbs are not used." >> "${GITHUB_STEP_SUMMARY}"
    echo "summary=Orbs are not used." >> "${GITHUB_OUTPUT}"
    exit 0
fi

mapfile -t NAMESPACES < <( \
  sed -n -E "${STANZA}{/^[[:space:]]*[^:]+[[:space:]]*:[[:space:]]*([^\/]+)\/([^@]+)@([^[:space:]:]+)[[:space:]]*\$/s//\1/p;}" "${CONFIG}" | sort -u \
)

for ns in "${NAMESPACES[@]}"; do
    { circleci --skip-update-check orb list "${ns}" --uncertified | sed -n -e 's/ (\([^)]*\))$/@\1/gp' \
        | sed -e '/Not published/d'
    } >> "${ORBS}" || true
    if [[ -z "${CIRCLECI_CLI_TOKEN:-}" ]]; then
        echo "${ns}: CIRCLECI_CLI_TOKEN must be set to retrieve private orbs" 1>&2
        break
    else
      { circleci --skip-update-check orb list --uncertified --private "${ns}" 2>/dev/null \
            | sed -n -e 's/ (\([^)]*\))$/@\1/gp' \
            | sed -e '/Not published/d'
      } >> "${ORBS}" || \
            echo "Failed to retrieve private orbs for ${ns}" 1>&2
    fi
done

for orb in "${IGNORED_ORBS[@]}"; do
    sed -i.orig -e "\#^${orb}@#d" "${ORBS}"
done

if [ ! -f "${ORBS}" ]; then
    echo "Failed to retrieve any latest versions" 1>&2
    exit 1
fi

sed -n -E "${STANZA}{/^[[:space:]]*[^:]+[[:space:]]*:[[:space:]]*([^\/]+)\/([^@]+)@([^[:space:]:]+)[[:space:]]*\$/s//\1\/\2@\3/p;}" "${CONFIG}" \
    | while read -r line; do
    orb="$(echo "${line}" | cut -f 1 -d'@')"
    version="$(echo "${line}" | cut -f 2 -d'@')"
    latest="$({ grep "${orb}" "${ORBS}" || true; } | cut -f 2 -d'@')"

    if [ -n "${latest:-}" ]; then
        orb_link="[\`${orb}\`](https://circleci.com/developer/orbs/orb/${orb})"
        if [ "${version}" != "${latest}" ]; then
            sed -i.orig -e "${STANZA}s!${orb}@${version}!${orb}@${latest}!g" "${CONFIG}"
            rm -f "${CONFIG}.orig"
            echo "- bumped ${orb_link} to ${latest} (was ${version})" >> "${OUT_UPDATES}"
        else
            echo "- ${orb_link} is already at ${latest}" >> "${OUT_LATEST}"
        fi
    fi
done


if [ -s "${OUT_UPDATES}" ]; then
    echo "### Updates" >> "${GITHUB_STEP_SUMMARY}"
    cat "${OUT_UPDATES}" >> "${GITHUB_STEP_SUMMARY}"
fi

if [ -s "${OUT_LATEST}" ]; then
    echo "### Already up to date" >> "${GITHUB_STEP_SUMMARY}"
    cat "${OUT_LATEST}" >> "${GITHUB_STEP_SUMMARY}"
fi

if [ -s "${OUT_UPDATES}" ]; then
    EOF="$(dd if=/dev/urandom bs=15 count=1 status=none | base64)"
    { echo "summary<<${EOF}"
      cat "${OUT_UPDATES}"
      echo "${EOF}"
    } >> "${GITHUB_OUTPUT}"
else
    echo "summary=No changes." >> "${GITHUB_OUTPUT}"
fi
