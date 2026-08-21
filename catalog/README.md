# catalog

This folder is written by the `Publish lab catalog` workflow in the private
source repository. Do not edit it by hand.

After the first successful run it contains:

```
index.json          the signed manifest list
index.json.sig      Ed25519 signature over index.json
subjects.yaml       the subject registry
devops/*.yaml       lab manifests
database/*.yaml
unix/*.yaml
```

The app verifies `index.json.sig` against a public key compiled into the
application, and each manifest against the SHA-256 recorded in `index.json`.
Anything that fails verification is rejected and the previously cached labs stay
in place.
