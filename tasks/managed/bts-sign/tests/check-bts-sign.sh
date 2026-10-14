#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
TASK="${REPO_ROOT}/tasks/managed/bts-sign/bts-sign.yaml"
PIPELINE="${REPO_ROOT}/pipelines/managed/push-artifacts-to-storage/push-artifacts-to-storage.yaml"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bts-sign-check.XXXXXX")
trap 'rm -rf "${WORK_DIR}"' EXIT
export WORK_DIR
EXPECTED_ARTIFACT="quay.io/example/data@sha256:test"
ARTIFACT_JSON=$(jq -cn --arg artifact "${EXPECTED_ARTIFACT}" '$artifact')

# Mock only the external CLI and API; execute the caller's actual script.
internal-request() {
    jq -n --args '$ARGS.positional' -- "$@" > "${WORK_DIR}/request-args.json"
    return "${MOCK_REQUEST_EXIT}"
}
kubectl() {
    jq -n --args '$ARGS.positional' -- "$@" > "${WORK_DIR}/get-args.json"
    [[ -f "${WORK_DIR}/request-args.json" ]] || return 92
    [[ "${MOCK_KUBECTL_EXIT}" == 0 ]] || return "${MOCK_KUBECTL_EXIT}"
    jq '.' "${WORK_DIR}/requests.json"
}
export -f internal-request kubectl

yq -r '.spec.steps[] | select(.name == "request-bts-sign") | .script' "${TASK}" > "${WORK_DIR}/caller.sh"
[[ -s "${WORK_DIR}/caller.sh" ]]
jq -n '{components: [{name: "allowed-rpm"}, {name: "other-rpm"}]}' > "${WORK_DIR}/snapshot.json"
jq -n '{status: {attribution: {author: "test-author"}}}' > "${WORK_DIR}/release.json"
cp "${WORK_DIR}/snapshot.json" "${WORK_DIR}/snapshot-original.json"

write_requests() {
    jq -n --argjson artifact "$1" --argjson count "${2:-1}" --arg status "${3:-True}" '{
      items: [range(0; $count) | {
        metadata: {name: "bts-sign-test"},
        status: {
          pipelineRun: "rhtap-releng-tenant/internalrequest-test",
          conditions: [{type: "InternalRequestSucceeded", status: $status}],
          results: {sourceDataArtifact: $artifact}
        }
      }]
    }' > "${WORK_DIR}/requests.json"
}

run_caller() {
    rm -f "${WORK_DIR}/result" "${WORK_DIR}/request-args.json" "${WORK_DIR}/get-args.json"
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
    TASKRUN_UID="test-task-run" \
    REQUEST_NAMESPACE="rhtap-releng-tenant" \
    REQUEST_TIMEOUT="2100" \
    PIPELINE_TIMEOUT="0h30m0s" \
    TASK_TIMEOUT="0h25m0s" \
    MOCK_REQUEST_EXIT="${MOCK_REQUEST_EXIT:-0}" \
    MOCK_KUBECTL_EXIT="${MOCK_KUBECTL_EXIT:-0}" \
    bash "${WORK_DIR}/caller.sh" > "${WORK_DIR}/output" 2>&1
}

check_request_args() {
    jq -e --arg artifact "${EXPECTED_ARTIFACT}" --arg allowed "$1" \
      --arg requester "$2" --arg account "${3:-release-service-account}" '. == [
        "--pipeline", "bts-sign",
        "-p", ("source_data_artifact=" + $artifact),
        "-p", "snapshot_path=run/snapshot.json",
        "-p", "data_path=run/data.json",
        "-p", ("allowed_components=" + $allowed),
        "-p", ("requester=" + $requester),
        "-p", "taskGitUrl=https://gitlab.cee.redhat.com/dtodorov/signing.git",
        "-p", "taskGitRevision=test-bts",
        "-l", "internal-services.appstudio.openshift.io/pipelinerun-uid=test-run",
        "-l", "internal-services.appstudio.openshift.io/taskrun-uid=test-task-run",
        "-t", "2100", "--service-account", $account,
        "--pipeline-timeout", "0h30m0s", "--task-timeout", "0h25m0s", "-s", "true"
      ]' "${WORK_DIR}/request-args.json" > /dev/null
}

expect_failure() {
    local status
    if run_caller; then
        printf '%s was accepted\n' "$1" >&2
        exit 1
    else
        status=$?
    fi
    [[ ! -f "${WORK_DIR}/result" ]]
    [[ -z "${2:-}" || "${status}" == "$2" ]]
}

# Submit and consume the passthrough result without any signing credentials.
jq -n '{signOptions: {allowedComponents: ["allowed-rpm", "absent-rpm"]}}' > "${WORK_DIR}/data.json"
cp "${WORK_DIR}/data.json" "${WORK_DIR}/data-original.json"
write_requests "${ARTIFACT_JSON}"
run_caller
[[ "$(<"${WORK_DIR}/result")" == "${EXPECTED_ARTIFACT}" ]]
[[ $(wc -c < "${WORK_DIR}/result") -eq ${#EXPECTED_ARTIFACT} ]]
[[ "$(<"${WORK_DIR}/output")" == *'Selected snapshot components: ["allowed-rpm"]'* ]]
[[ "$(<"${WORK_DIR}/output")" == *'BTS PipelineRun: rhtap-releng-tenant/internalrequest-test'* ]]
check_request_args '["allowed-rpm","absent-rpm"]' test-author
jq -e '. == ["get", "internalrequest", "-n", "rhtap-releng-tenant",
  "-l", "internal-services.appstudio.openshift.io/taskrun-uid=test-task-run", "-o", "json"]' \
  "${WORK_DIR}/get-args.json" > /dev/null
cmp "${WORK_DIR}/snapshot.json" "${WORK_DIR}/snapshot-original.json"
cmp "${WORK_DIR}/data.json" "${WORK_DIR}/data-original.json"

# A different worker result proves the caller reads status instead of copying its input.
write_requests '"quay.io/example/worker-result@sha256:returned"'
run_caller
[[ "$(<"${WORK_DIR}/result")" == 'quay.io/example/worker-result@sha256:returned' ]]

# Missing allowlist/attribution still submits; service account selection matches rh-sign-rpm.
write_requests "${ARTIFACT_JSON}"
jq -n '{signOptions: {signPipelineServiceAccount: "bts-test-account"}}' > "${WORK_DIR}/data.json"
jq -n '{}' > "${WORK_DIR}/release.json"
run_caller
[[ "$(<"${WORK_DIR}/output")" == *'Selected snapshot components: []'* ]]
check_request_args '[]' NOT_ENOUGH_DATA bts-test-account
rm "${WORK_DIR}/release.json"
run_caller
check_request_args '[]' NOT_ENOUGH_DATA bts-test-account

# Submission, rejection/execution failure, timeout, and result reads must stop the caller.
for status in 1 21 22 124; do
    MOCK_REQUEST_EXIT="${status}" expect_failure "Request exit ${status}" "${status}"
    [[ -f "${WORK_DIR}/request-args.json" && ! -f "${WORK_DIR}/get-args.json" ]]
done
MOCK_KUBECTL_EXIT=1 expect_failure 'Failed request status read'

for artifact in null '""' false '[]' '{}' 12; do
    write_requests "${artifact}"
    expect_failure "Invalid result ${artifact}"
done
for count in 0 2; do
    write_requests "${ARTIFACT_JSON}" "${count}"
    expect_failure "Request count ${count}"
done
for status in False Unknown; do
    write_requests "${ARTIFACT_JSON}" 1 "${status}"
    expect_failure "Unsuccessful request status ${status}"
done

# Invalid input is distinct from missing signing configuration.
jq -n '{signOptions: {allowedComponents: "allowed-rpm"}}' > "${WORK_DIR}/data.json"
expect_failure 'Invalid allowlist'
[[ ! -f "${WORK_DIR}/request-args.json" ]]
jq -n '{signOptions: {allowedComponents: false}}' > "${WORK_DIR}/data.json"
expect_failure 'Boolean allowlist'
[[ ! -f "${WORK_DIR}/request-args.json" ]]
jq -n '{signOptions: {signPipelineServiceAccount: []}}' > "${WORK_DIR}/data.json"
expect_failure 'Invalid service account'
[[ ! -f "${WORK_DIR}/request-args.json" ]]
jq -n '{}' > "${WORK_DIR}/data.json"
jq -n '{components: [{name: null}]}' > "${WORK_DIR}/snapshot.json"
expect_failure 'Invalid snapshot'
[[ ! -f "${WORK_DIR}/request-args.json" ]]

# Context and timeout values must be wired into the extracted caller script's environment.
yq -o=json "${TASK}" | jq -e '
  (.spec.params | map({key: .name, value: .default}) | from_entries) as $defaults |
  (.spec.steps[] | select(.name == "request-bts-sign") | .env |
    map({key: .name, value: .value}) | from_entries) as $env |
  $defaults.requestTimeout == "2100" and $defaults.pipelineTimeout == "0h30m0s" and
  $defaults.taskTimeout == "0h25m0s" and $defaults.signingRevision == "rok-bts-iterdev" and
  $env.TASKRUN_UID == "$(context.taskRun.uid)" and
  $env.REQUEST_NAMESPACE == "$(context.taskRun.namespace)" and
  $env.REQUEST_TIMEOUT == "$(params.requestTimeout)" and
  $env.PIPELINE_TIMEOUT == "$(params.pipelineTimeout)" and $env.TASK_TIMEOUT == "$(params.taskTimeout)"
' > /dev/null

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

printf 'BTS submission, result handoff, failure paths, and import/promotion wiring passed.\n'
