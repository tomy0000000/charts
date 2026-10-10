# clickhouse

Helm chart that runs one [ClickHouse](https://clickhouse.com) server from the
official image: a StatefulSet with a persistent volume, a Service on the HTTP
and native ports, and a NetworkPolicy that admits only pods from the same
namespace. No Keeper, no replicas, no sharding: the shape a single app's
analytics store takes.

## Install

```bash
helm repo add tomy0000000 https://charts.tomy.me
helm install clickhouse tomy0000000/clickhouse \
  --namespace plausible --create-namespace \
  --values values.yaml
```

The stock configuration stays in the image. Settings go in as files under
`config.d` and `users.d`, which is how ClickHouse expects overrides:

```yaml
image:
  tag: 24.12.6.70-alpine

persistence:
  storageClass: do-block-storage-retain
  size: 5Gi

resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    memory: 1Gi

configFiles:
  low-resources.xml: |
    <clickhouse>
        <mark_cache_size>524288000</mark_cache_size>
    </clickhouse>

usersFiles:
  low-resources.xml: |
    <clickhouse>
        <profiles>
            <default>
                <max_threads>1</max_threads>
            </default>
        </profiles>
    </clickhouse>

# Keep the image from writing its own users.d file on first start.
extraEnv:
  - name: CLICKHOUSE_SKIP_USER_SETUP
    value: "1"
```

The `default` user ships with no password. The NetworkPolicy is what keeps
that acceptable, so leave `networkPolicy.enabled` on unless you define users
of your own in `usersFiles`.

## Backups

With `backup.enabled`, a CronJob has the server run `BACKUP DATABASE ... TO
S3()` for each listed database, a full backup per run into its own folder,
`<url>/<database>/<UTC timestamp>`. The server does the upload, the job only
issues the statement. The S3 key comes from a Secret you manage, with
`accessKeyId` and `secretAccessKey` keys by default. It goes into the server's
environment, and the statements name only the URL, so the key shows up in no
query log and no client error. A rotated key takes effect on the next pod
restart.

```yaml
backup:
  enabled: true
  schedule: "0 3 * * *"
  url: https://<account>.r2.cloudflarestorage.com/<bucket>
  databases:
    - plausible_events_db
  existingSecret: r2-backup
```

Nothing prunes old folders. Put a lifecycle rule on the bucket.

To start a server from one of those folders, set `backup.recoverFrom` to it
before the first install. A `post-install` hook waits for the server and runs
`RESTORE ALL` from that folder, once. Later upgrades ignore the value, so it
can stay in place as a record of where the data came from. The restore needs
`backup.existingSecret` even if the schedule is off.

## Values

See [values.yaml](values.yaml). Every key is commented.
