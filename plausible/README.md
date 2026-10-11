# plausible

Helm chart that runs the [Plausible Community Edition](https://github.com/plausible/community-edition)
web app, and only that. The compose file upstream ships bundles a Postgres
and a ClickHouse; this chart expects you to bring both, and reads their
addresses from a Secret along with the keys Plausible needs.

## Install

```bash
helm repo add tomy0000000 https://charts.tomy.me
helm install plausible tomy0000000/plausible \
  --namespace plausible --create-namespace \
  --values values.yaml
```

One Secret must exist in the namespace, or arrive with the release through
`extraObjects`. Every key in it becomes an environment variable, so it holds
whatever Plausible's [configuration](https://github.com/plausible/community-edition/wiki/configuration)
calls for that is secret:

```yaml
baseURL: https://plausible.example.com

existingSecret: plausible # keys: SECRET_KEY_BASE, TOTP_VAULT_KEY, DATABASE_URL

env:
  CLICKHOUSE_DATABASE_URL: http://clickhouse:8123/plausible_events_db
  DISABLE_REGISTRATION: invite_only

# For example, External Secrets Operator composing the Secret from a vault.
extraObjects:
  - apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: plausible
    spec:
      secretStoreRef:
        kind: ClusterSecretStore
        name: onepassword
      target:
        name: plausible
        template:
          data:
            SECRET_KEY_BASE: "{{ .secretKeyBase }}"
            TOTP_VAULT_KEY: "{{ .totpVaultKey }}"
            DATABASE_URL: "postgres://plausible:{{ .password }}@postgres:5432/plausible"
      data:
        - secretKey: secretKeyBase
          remoteRef: { key: plausible-secret_key_base/credential }
        - secretKey: totpVaultKey
          remoteRef: { key: plausible-totp_vault_key/credential }
        - secretKey: password
          remoteRef: { key: postgres-plausible/credential }
```

Generate the two keys once and never change them: `SECRET_KEY_BASE` with
`openssl rand -base64 48`, `TOTP_VAULT_KEY` with `openssl rand -base64 32`.
Sessions and every user's 2FA secret are bound to them.

An init container runs `db createdb` and `db migrate` before each start, as
the upstream compose file does, so a version bump is a tag change.

## Values

See [values.yaml](values.yaml). Every key is commented.
