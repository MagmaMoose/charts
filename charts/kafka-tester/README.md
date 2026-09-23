# kafka-tester

Deploys [kafka-tester](https://github.com/MagmaMoose/kafka-tester): a small web UI
that checks a Kafka endpoint from inside the cluster. It lists the brokers as they
advertise themselves, produces a message, reads the newest ones back, and when any
of that fails it says why (connection refused, DNS, TLS handshake).

```bash
helm install kafka-tester oci://ghcr.io/magmamoose/charts/kafka-tester \
  --namespace kafka-tester --create-namespace \
  --set-json 'targets=[{"name": "in-cluster", "bootstrap": "kafka.kafka.svc.cluster.local:9092"}]'

kubectl -n kafka-tester port-forward svc/kafka-tester 8000:80
```

Then open <http://localhost:8000>.

## What it creates

| | |
|---|---|
| Deployment | gunicorn, read-only root filesystem, uid 10001 |
| Service, ServiceAccount, optional Ingress | |

## Values that matter

| Value | Default | |
|---|---|---|
| `targets` | `[]` | Preset endpoints: `name`, `bootstrap` (`host:port[,host:port...]`), and optionally `tls`, `verify` (default true) and `description`. |
| `config.allowCustom` | `true` | `false` limits the UI to `targets`. |
| `config.defaultTopic` | `kafka-tester` | |
| `config.timeoutMs` | `10000` | Bounds each Kafka request. |
| `config.createTopics` | `true` | Create a missing topic before producing to it. |
| `config.ipEchoUrl` | `https://api.ipify.org` | Used by `/debug/ip`; empty turns it off. |
| `caBundle.secretName` / `caBundle.configMapName` | | A private CA for TLS targets, read from `caBundle.key`. |
| `ingress.enabled` | `false` | See below before turning it on. |
| `image.digest` | | Pins the image by digest as well as tag. |

## Things to know

**The UI has no login.** It connects wherever it is asked to and writes to any topic
it can reach. The Ingress is off by default for that reason; put authentication in
front of it before exposing it, and set `config.allowCustom: false` where it should
only reach its presets.

**Test from where the clients are.** A pod in the cluster sees the cluster's DNS,
network policies and egress address, so a check that passes here and fails from a
laptop (or the other way round) points at the network between them, not at Kafka.

## Guards

The chart refuses to render, with the reason, when:

- `config.allowCustom` is false and `targets` is empty, which would leave nothing to test;
- two targets share a name, which the app refuses at startup;
- `caBundle` names both a Secret and a ConfigMap.
