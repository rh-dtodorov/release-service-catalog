# push-artifacts-to-storage pipeline

Tekton pipeline to push rpms into the artifact storage instance.
On import, BTS runs through an InternalRequest and its returned artifact is passed to Koji.
The mock BTS worker reconstructs selected RPM bundles without generating signatures;
probe mode skips the Koji import and returns probe evidence with the release data.
Promotion does not run BTS.

## Parameters

| Name                            | Description                                                                                                                        | Optional | Default value                                             |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------------------------------|
| release                         | The namespaced name (namespace/name) of the Release custom resource initiating this pipeline execution                             | No       | -                                                         |
| releasePlan                     | The namespaced name (namespace/name) of the releasePlan                                                                            | No       | -                                                         |
| releasePlanAdmission            | The namespaced name (namespace/name) of the releasePlanAdmission                                                                   | No       | -                                                         |
| releaseServiceConfig            | The namespaced name (namespace/name) of the releaseServiceConfig                                                                   | No       | -                                                         |
| snapshot                        | The namespaced name (namespace/name) of the snapshot                                                                               | No       | -                                                         |
| taskGitUrl                      | The url to the git repo where the release-service-catalog tasks to be used are stored                                              | Yes      | https://github.com/konflux-ci/release-service-catalog.git |
| taskGitRevision                 | The revision in the taskGitUrl repo to be used                                                                                     | No       | -                                                         |
| signingRepo                     | Repository containing the internal BTS pipeline and worker task                                                                    | Yes      | https://gitlab.cee.redhat.com/dtodorov/signing.git        |
| signingRevision                 | Revision of the internal BTS pipeline and worker task                                                                              | Yes      | rok-bts-iterdev                                           |
| enterpriseContractPolicy        | JSON representation of the EnterpriseContractPolicy                                                                                | Yes      | brew-rhel-sst-prod                                        |
| enterpriseContractExtraRuleData | Extra rule data to be merged into the policy specified in params.enterpriseContractPolicy. Use syntax "key1=value1,key2=value2..." | Yes      | pipeline_intention=release                                |
| ociStorage                      | The OCI repository where the Trusted Artifacts are stored                                                                          | Yes      | quay.io/konflux-ci/release-service-trusted-artifacts      |
| ociArtifactExpiresAfter         | Retention of BTS output artifacts; empty means no expiration                                                                       | Yes      | 1d                                                        |
| orasOptions                     | oras options to pass to Trusted Artifacts calls                                                                                    | Yes      | ""                                                        |
| trustedArtifactsDebug           | Flag to enable debug logging in trusted artifacts. Set to a non-empty string to enable                                             | Yes      | ""                                                        |
| dataDir                         | The location where data will be stored                                                                                             | Yes      | /var/workdir/release                                      |
