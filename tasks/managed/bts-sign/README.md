# bts-sign

Submits an InternalRequest for snapshot-based BTS, waits for completion, and returns the
worker's sourceDataArtifact result. Reads signOptions.allowedComponents and Release attribution.
The current worker returns the input Trusted Artifact unchanged without signing RPMs.
Signing keys are not required for the passthrough worker.

## Parameters

| Name                  | Description                                                              | Optional | Default value                                      |
|-----------------------|--------------------------------------------------------------------------|----------|----------------------------------------------------|
| snapshotPath          | Relative path to the reduced snapshot spec in the input Trusted Artifact | No       | -                                                  |
| dataPath              | Relative path to the merged release data in the input Trusted Artifact   | No       | -                                                  |
| releasePath           | Relative path to the collected Release JSON used for attribution         | No       | -                                                  |
| sourceDataArtifact    | Input Trusted Artifact reference passed to the BTS worker                | No       | -                                                  |
| pipelineRunUid        | Release PipelineRun UID for the InternalRequest correlation label        | No       | -                                                  |
| requestTimeout        | Seconds to wait for the InternalRequest, including pipeline startup      | Yes      | 2100                                               |
| pipelineTimeout       | Pipeline timeout for the BTS InternalRequest                             | Yes      | 0h30m0s                                            |
| taskTimeout           | Task timeout for the BTS InternalRequest                                 | Yes      | 0h25m0s                                            |
| dataDir               | Directory into which the input Trusted Artifact is extracted             | Yes      | /var/workdir/release                               |
| taskGitUrl            | Catalog repository URL for resolving the Trusted Artifact StepAction     | No       | -                                                  |
| taskGitRevision       | Catalog revision for resolving the Trusted Artifact StepAction           | No       | -                                                  |
| signingRepo           | Repository containing the internal BTS pipeline and worker task          | Yes      | https://gitlab.cee.redhat.com/dtodorov/signing.git |
| signingRevision       | Revision of the internal BTS pipeline and worker task                    | Yes      | rok-bts-iterdev                                    |
| trustedArtifactsDebug | Non-empty value enables Trusted Artifact debug logging                   | Yes      | ""                                                 |
| orasOptions           | Additional options for extracting the input Trusted Artifact             | Yes      | ""                                                 |
| caTrustConfigMapName  | ConfigMap containing the trusted CA bundle                               | Yes      | trusted-ca                                         |
| caTrustConfigMapKey   | CA bundle entry in the trusted CA ConfigMap                              | Yes      | ca-bundle.crt                                      |
