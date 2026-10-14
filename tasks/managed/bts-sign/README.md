# bts-sign

Logging-only BTS caller for snapshot-based RPM signing. Reads signOptions.allowedComponents
and Release attribution, logs the intended internal bts-sign invocation, and returns the
input Trusted Artifact unchanged. No InternalRequest is submitted and no RPMs are signed.
Missing signing configuration does not block passthrough.

## Parameters

| Name                  | Description                                                                | Optional | Default value                                      |
|-----------------------|----------------------------------------------------------------------------|----------|----------------------------------------------------|
| snapshotPath          | Relative path to the reduced snapshot spec in the input Trusted Artifact   | No       | -                                                  |
| dataPath              | Relative path to the merged release data in the input Trusted Artifact     | No       | -                                                  |
| releasePath           | Relative path to the collected Release JSON used for attribution           | No       | -                                                  |
| sourceDataArtifact    | Input Trusted Artifact reference, returned unchanged by this skeleton      | No       | -                                                  |
| pipelineRunUid        | Release PipelineRun UID for the intended InternalRequest correlation label | No       | -                                                  |
| dataDir               | Directory into which the input Trusted Artifact is extracted               | Yes      | /var/workdir/release                               |
| taskGitUrl            | Catalog repository URL for resolving the Trusted Artifact StepAction       | No       | -                                                  |
| taskGitRevision       | Catalog revision for resolving the Trusted Artifact StepAction             | No       | -                                                  |
| signingRepo           | Repository containing the internal BTS pipeline whose invocation is logged | Yes      | https://gitlab.cee.redhat.com/dtodorov/signing.git |
| signingRevision       | Revision of the internal BTS pipeline whose invocation is logged           | Yes      | main                                               |
| trustedArtifactsDebug | Non-empty value enables Trusted Artifact debug logging                     | Yes      | ""                                                 |
| orasOptions           | Additional options for extracting the input Trusted Artifact               | Yes      | ""                                                 |
| caTrustConfigMapName  | ConfigMap containing the trusted CA bundle                                 | Yes      | trusted-ca                                         |
| caTrustConfigMapKey   | CA bundle entry in the trusted CA ConfigMap                                | Yes      | ca-bundle.crt                                      |
