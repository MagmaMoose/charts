# charts

Helm charts for [MagmaMoose](https://github.com/MagmaMoose) infrastructure,
published as OCI artifacts to `ghcr.io/magmamoose/charts`.

There is no chart repository to add, no `index.yaml`, and no `gh-pages` branch:

```bash
helm install janeway oci://ghcr.io/magmamoose/charts/janeway --version 0.1.0
```

Flux points at the same place with a `type: oci` HelmRepository.

## Charts

| Chart | |
|---|---|
| [janeway](charts/janeway) | [Janeway](https://github.com/openlibhums/janeway) — journal, preprint and book publishing platform |

## Conventions

**Chart version and appVersion move independently.** The chart version tracks
this repository and is set at release time by GitVersion. `appVersion` names the
application image tag and is bumped in `Chart.yaml` when that image is upgraded.
Charts here use `appVersion` as the default image tag, so the two must not be
forced equal.

**Guards over documentation.** Configuration mistakes that would be slow to
diagnose in a live cluster — a missing hostname, several replicas on a
ReadWriteOnce volume with no node pinning — fail `helm template` with the reason
instead. See `templates/_guards.tpl` in a chart, and the CI job that asserts each
guard still fires.

**`values.schema.json` for shape, guards for context.** JSON Schema validates
types and enums; it cannot express "this is only wrong given that other value",
and its errors are poor. Cross-field rules live in the guards.

**Comments explain why, not what.** A comment that restates the YAML beneath it
is noise; one that records the failure a line prevents is the reason the line
survives the next refactor.

## Releasing

Push to `main` with a conventional-commit message. Diatreme computes the next
version, tags it, publishes the GitHub Release, and this repo's workflow then
packages every chart at that version and pushes it to GHCR.

## Contributing

`ct lint` plus a render-and-validate pass against the real Kubernetes API
schemas runs on every pull request. To reproduce locally:

```bash
helm lint charts/janeway --values charts/janeway/ci/default-values.yaml
helm template t charts/janeway --values charts/janeway/ci/default-values.yaml | kubeconform -strict -summary
```
