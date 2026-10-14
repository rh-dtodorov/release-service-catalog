#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
TASK="${REPO_ROOT}/tasks/managed/bts-sign/bts-sign.yaml"
PIPELINE="${REPO_ROOT}/pipelines/managed/push-artifacts-to-storage/push-artifacts-to-storage.yaml"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bts-sign-check.XXXXXX")
trap 'rm -rf "${WORK_DIR}"' EXIT
export WORK_DIR
EXPECTED_ARTIFACT="quay.io/example/data@sha256:test"

# Any accidental request submission fails the check and leaves evidence.
internal-request() {
    printf 'Unexpected InternalRequest submission\n' > "${WORK_DIR}/request-submitted"
    return 91
}
export -f internal-request

yq -r '.spec.steps[] | select(.name == "log-bts-intention") | .script' "${TASK}" > "${WORK_DIR}/caller.sh"
jq -n '{components: [{name: "allowed-rpm"}, {name: "other-rpm"}]}' > "${WORK_DIR}/snapshot.json"
jq -n '{status: {attribution: {author: "test-author"}}}' > "${WORK_DIR}/release.json"
cp "${WORK_DIR}/snapshot.json" "${WORK_DIR}/snapshot-original.json"

run_caller() {
    DATA_FILE="${WORK_DIR}/data.json" \
    SNAPSHOT_FILE="${WORK_DIR}/snapshot.json" \
    RELEASE_FILE="${WORK_DIR}/release.json" \
    SNAPSHOT_PATH="run/snapshot.json" \
    DATA_PATH="run/data.json" \
    SOURCE_DATA_ARTIFACT="${EXPECTED_ARTIFACT}" \
    RESULT_FILE="${WORK_DIR}/result" \
    SIGNING_REPO="https://gitlab.cee.redhat.com/dtodorov/signing.git" \
    SIGNING_REVISION="test-bts" \
    PIPELINERUN_UID="test-run" \
    bash "${WORK_DIR}/caller.sh" > "${WORK_DIR}/output" 2>&1
}

# No keytab, alias, or signing service account is configured.
jq -n '{signOptions: {allowedComponents: ["allowed-rpm", "absent-rpm"]}}' > "${WORK_DIR}/data.json"
cp "${WORK_DIR}/data.json" "${WORK_DIR}/data-original.json"
run_caller
[[ "$(<"${WORK_DIR}/result")" == "${EXPECTED_ARTIFACT}" ]]
[[ $(wc -c < "${WORK_DIR}/result") -eq ${#EXPECTED_ARTIFACT} ]]
[[ "$(<"${WORK_DIR}/output")" == *'Selected snapshot components: ["allowed-rpm"]'* ]]
[[ "$(<"${WORK_DIR}/output")" == *'Intended command (not executed): internal-request --pipeline bts-sign'* ]]
[[ "$(<"${WORK_DIR}/output")" == *'requester=test-author'* ]]
[[ ! -f "${WORK_DIR}/request-submitted" ]]
cmp "${WORK_DIR}/snapshot.json" "${WORK_DIR}/snapshot-original.json"
cmp "${WORK_DIR}/data.json" "${WORK_DIR}/data-original.json"

# Missing allowlist and attribution must still pass without selecting RPMs.
jq -n '{}' > "${WORK_DIR}/data.json"
jq -n '{}' > "${WORK_DIR}/release.json"
run_caller
[[ "$(<"${WORK_DIR}/output")" == *'Selected snapshot components: []'* ]]
[[ "$(<"${WORK_DIR}/output")" == *'requester=NOT_ENOUGH_DATA'* ]]

# Invalid input is distinct from missing signing configuration.
jq -n '{signOptions: {allowedComponents: "allowed-rpm"}}' > "${WORK_DIR}/data.json"
if run_caller; then
    printf 'Invalid allowlist was accepted\n' >&2
    exit 1
fi
jq -n '{signOptions: {allowedComponents: false}}' > "${WORK_DIR}/data.json"
if run_caller; then
    printf 'Boolean allowlist was accepted\n' >&2
    exit 1
fi
jq -n '{}' > "${WORK_DIR}/data.json"
jq -n '{components: [{name: null}]}' > "${WORK_DIR}/snapshot.json"
if run_caller; then
    printf 'Invalid snapshot was accepted\n' >&2
    exit 1
fi

# Check the actual DAG and result handoff, including promotion isolation.
yq -o=json "${PIPELINE}" | jq -e '
  .spec.tasks as $tasks |
  ($tasks[] | select(.name == "bts-sign")) as $bts |
  ($tasks[] | select(.name == "push-rpm-to-koji")) as $koji |
  $bts.runAfter == ["verify-conforma"] and
  $koji.runAfter == ["bts-sign"] and
  $bts.when == $koji.when and
  $bts.when == [{input: "$(tasks.collect-task-params.results.extractedValues[3])",
                 operator: "notin", values: ["promote"]}] and
  ([$bts.params[] | select(.name == "sourceDataArtifact") | .value] ==
    ["$(tasks.reduce-snapshot.results.sourceDataArtifact)"]) and
  ([$koji.params[] | select(.name == "sourceDataArtifact") | .value] ==
    ["$(tasks.bts-sign.results.sourceDataArtifact)"]) and
  all($tasks[] | select(.name == "push-artifacts-to-storage" or .name == "promote-koji-draft-build");
      ([.params[] | select(.name == "sourceDataArtifact") | .value] ==
        ["$(tasks.reduce-snapshot.results.sourceDataArtifact)"]) and
      ([.runAfter[] | select(. == "bts-sign")] | length) == 0 and
      .when == [{input: "$(tasks.collect-task-params.results.extractedValues[3])",
                 operator: "in", values: ["promote"]}])
' > /dev/null

printf 'BTS caller passthrough, input checks, and import/promotion wiring passed.\n'
