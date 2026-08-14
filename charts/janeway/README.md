# janeway

Deploys [Janeway](https://github.com/openlibhums/janeway) — a publishing
platform for journals, preprints, conference proceedings and books.

The image is [`ghcr.io/tengen-systems/janeway`](https://github.com/tengen-systems/janeway),
which is a production build of upstream: gunicorn instead of `runserver`,
WhiteNoise for static files, a settings module that works behind a reverse
proxy, and two patches. Upstream's own container is a development image.

```bash
helm install janeway oci://ghcr.io/magmamoose/charts/janeway \
  --set config.siteDomain=journals.example.com \
  --set database.host=postgres-rw.database.svc.cluster.local \
  --set database.existingSecret=janeway-db \
  --set secretKey.existingSecret=janeway-secret-key
```

The chart refuses to render without those — see [Guards](#guards).

## What it creates

| | |
|---|---|
| Deployment | gunicorn, gthread workers |
| Job (`pre-install`, `pre-upgrade`) | `manage.py migrate` |
| Job (`post-install`, `post-upgrade`) | press, first journal, superuser, default settings, plugins |
| CronJobs | scheduled tasks, one per job — six enabled by default |
| PVC | uploaded manuscripts, galleys, media, XSL |
| Service, optional Ingress, PDB, HPA, NetworkPolicy, ServiceAccount | |

## Things that will bite you

**`config.siteDomain` must equal the `Press.domain` database row.** Janeway
resolves which press or journal a request belongs to from the `Host` header
alone. A request that matches nothing is redirected to `DEFAULT_HOST` — so a
mismatch does not 404, it silently bounces visitors off the site. That row is
written **once**, by the bootstrap job; changing the hostname later is a
database `UPDATE`, not a values change.

**The volume is not optional.** Janeway writes uploads with plain `open()` to
`BASE_DIR/files` and `BASE_DIR/media`. It does not use django-storages, so
object storage is not a drop-in. Without `persistence.enabled` every uploaded
manuscript and galley is lost on restart.

**`ReadWriteOnce` is per node, not per pod.** Several replicas can share one RWO
volume, but only if they all schedule onto the same node. The chart refuses to
render `replicaCount > 1` on a RWO volume unless you have also set a
`nodeSelector` or `affinity`. The default strategy is `Recreate` for the same
reason.

**Give the cache its own database index.** Django's `RedisCache.clear()` issues
`FLUSHDB`, and Janeway calls it whenever an editor saves settings. Pointed at a
shared Redis or Valkey without an index (`…:6379`), that wipes index 0 —
somebody else's data. Use `…:6379/6`. `NOTES.txt` warns when the URL has no
index.

**Scheduled work is CronJobs, not the application's own scheduler.** Upstream
runs `CronTask.run_tasks()` from middleware on *every HTTP request*, unlocked;
the image removes that middleware and patches the row claim. Do not re-enable
it.

## Values

Full list in [`values.yaml`](values.yaml), which carries the reasoning inline.
The ones you cannot skip:

| Key | Notes |
|---|---|
| `config.siteDomain` | public FQDN. Required. |
| `database.host` | required |
| `database.existingSecret` | required unless `database.password` |
| `secretKey.existingSecret` | required unless `secretKey.value` |

`secretKey` has no default and never will: upstream hardcodes a `SECRET_KEY`
literal that is published in a public AGPL repository. An install that did not
override it would boot, serve and accept logins while signing session cookies
and password-reset tokens with a key anyone can read. The image refuses to start
on that literal.

Worth setting early:

| Key | Default | |
|---|---|---|
| `config.cacheUrl` | `""` | per-process cache without it — fine for one replica |
| `email.host` | `""` | without it mail is printed to the log, not sent |
| `config.enableFullTextSearch` | `false` | on = full galley text in Postgres, the dominant growth term |
| `bootstrap.superuser.email` | `""` | no superuser is created without it |
| `persistence.storageClass` | cluster default | |
| `nodeSelector` | `{}` | needed for multi-replica on RWO |

### CronJobs

Six are on by default: `execute-cron-tasks` (drains the deferred-email queue
every 5 minutes), `send-reminders`, `send-publication-notifications`,
`generate-sitemaps`, `generate-robots`, `clear-sessions`. Sessions are stored in
the database and nothing upstream prunes them, which is why that last one
matters.

Eight more ship disabled because they need an integration or are expensive:
`update-article-metrics`, `poll-crossref`, `import-ror-data`, `match-ror-ids`,
`store-ithenticate-scores`, `check-mailgun-stat`, `generate-site-search-data`.

Enable, retime or add one from values:

```yaml
cronJobs:
  jobs:
    poll-crossref:
      enabled: true
      schedule: "0 */2 * * *"
      command: ["poll_crossref"]
```

## Guards

`helm template` fails fast, with the reason, on: a missing `config.siteDomain`,
`database.host` or credential; several replicas or autoscaling on a
ReadWriteOnce volume with no node pinning; `RollingUpdate` in the same
situation; a superuser email with no password source; and `ingress.enabled` with
no hosts. Each of those is otherwise a slow, confusing failure in a live
cluster rather than an error at render time.

## Upgrading

`migrate` runs as a pre-upgrade hook and the bootstrap job re-runs
`load_default_settings` and `install_plugins`, so settings added by a new
Janeway release land automatically. Back up the database first — Janeway
migrations are not reversible.
