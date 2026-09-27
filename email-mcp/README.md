# email-mcp

Helm chart that runs [mcp-email-server](https://github.com/Wh1isper/mcp-email-server)
as a remote MCP server for a mailcow mailbox, so Claude (claude.ai, Claude Code,
mobile) can read and organise mail over IMAP.

## Install

```bash
helm repo add tomy0000000 https://charts.tomy.me
helm install email-mcp tomy0000000/email-mcp \
  --namespace email-mcp --create-namespace \
  --values values.yaml
```

Two Secrets must exist in the namespace, or arrive with the release through
`extraObjects`:

```yaml
host: email-mcp.example.com

auth:
  existingSecret: email-mcp-token
  existingSecretKey: token

account:
  existingSecret: email-mcp-imap # keys: username (the address), password
  imap:
    host: mail.example.com
    port: 993

persistence:
  storageClass: do-block-storage-retain
  size: 1Gi

# For example, External Secrets Operator pulling both from a vault.
extraObjects:
  - apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: email-mcp-imap
    spec:
      refreshInterval: 1h
      secretStoreRef:
        kind: ClusterSecretStore
        name: onepassword
      target:
        name: email-mcp-imap
      data:
        - secretKey: username
          remoteRef:
            key: mailcow-email-mcp/username
        - secretKey: password
          remoteRef:
            key: mailcow-email-mcp/credential
```

Nothing is left to do by hand after install. The server reads the mailbox
from the Secret on every start, so a fresh volume and an old one converge, and
a rotated password takes effect on `kubectl rollout restart`.

## The mailbox

mcp-email-server composes an account from `MCP_EMAIL_SERVER_*` environment
variables, the mechanism upstream documents for containers. The chart maps
`account.existingSecret` and `account.imap.*` onto them. Upstream calls the
file-and-environment mode "legacy" next to its newer managed SQLite catalog,
but 1.9.1 neither warns about it nor announces its removal, and the catalog
would only add an interactive `account add` and a plaintext copy of the
password on the volume (Linux has no keyring there).

The send policy is pinned to deny (`MCP_EMAIL_SERVER_ALLOWED_RECIPIENTS=""`)
and no outgoing server is configured. Pair that with a mailcow app password
that has `imap_access` only, and the server cannot send no matter what it is
asked. The chart offers no way to enable sending.

## Exposure

The Ingress template is off by default. With a Gateway API controller, point
an HTTPRoute for `host` at the Service (port `80`, named `http`), which is the
Caddy sidecar. Whatever fronts the proxy must forward `Host` unchanged, keep
the `/mcp` and `/<token>/mcp` paths intact, and raise or disable its request
timeout for them: MCP responses are server-sent event streams that outlive the
default 15 s of Envoy Gateway and the 60 s of ingress-nginx, and a timeout
there surfaces as a 504 mid-call.

The Ingress, when enabled, routes `/` (not just `/mcp`) because the
secret-path form lives at `/<token>/mcp`. No other path does anything: the
proxy answers 401.

## Authentication

The server has no auth of its own, so the proxy checks one shared token. Three
ways to present it, each individually switchable under `auth.methods`:

| Method                          | Client                                        |
| ------------------------------- | --------------------------------------------- |
| `Authorization: Bearer <token>` | Claude Code (`claude mcp add --header ...`)   |
| `X-Api-Key: <token>`            | Anything that lets you set a request header   |
| `https://<host>/<token>/mcp`    | claude.ai custom connectors with "No sign-in" |

claude.ai needs the third form: its first probe carries no custom headers, and
a 401 sends it down an OAuth flow the server does not implement. The proxy's
access log and its error log both redact the path segment and both headers.

`auth.existingSecret` / `auth.existingSecretKey` is the recommended path:
the token lives wherever your other secrets do. Otherwise `auth.token` sets
it inline, and with neither one is generated on first install and reused on
upgrade (the chart reads it back with `lookup`, so `helm template` alone will
show a fresh value every run).

## Storage and permissions

The volume only holds the metadata index, a rebuildable cache of message
headers that makes listing a large mailbox fast. mcp-email-server opens it
only if its directory is owned by the running uid with mode 0700 and no
ancestor is group- or world-writable, which rules out `fsGroup`. A root init
container creates `/data/config` with the right owner and mode. Turn off
`volumePermissions.enabled` if root init containers are not allowed in your
cluster, and prepare the directory another way. If the directory is not
right, the server logs a warning and answers every listing from IMAP
directly.

## Local checks

```bash
helm lint email-mcp --values email-mcp/ci/default-values.yaml
email-mcp/test/smoke.sh
```

`test/smoke.sh` runs the two images with Docker the way the pod does (shared
network namespace, same init step, same environment, Caddyfile rendered from
this chart) and checks the three auth paths, the 401 cases, that the account
from the environment is listed with sending off, that the metadata index
opens, and that neither log contains the token or the password. Needs `helm`
and `docker`.

## Values

See `values.yaml`; every key is commented. The ones you will actually set:

| Key                                              | What it is                                                                      |
| ------------------------------------------------ | ------------------------------------------------------------------------------- |
| `host`                                           | Public hostname. Ingress host and server allowlist.                             |
| `auth.existingSecret` / `auth.existingSecretKey` | Secret holding the shared token.                                                |
| `account.existingSecret`                         | Secret with the address (`usernameKey`) and password (`passwordKey`). Required. |
| `account.imap.host` / `port` / `starttls`        | Where the mailbox is.                                                           |
| `persistence.*`                                  | Size, storage class, or an existing claim.                                      |
| `extraObjects`                                   | Manifests shipped with the release, such as ExternalSecrets.                    |
| `ingress.*`                                      | Class, annotations (cert-manager), TLS secret name.                             |
| `auth.methods.*`                                 | Disable the forms you do not use.                                               |
| `image.tag`                                      | Pin a different mcp-email-server version.                                       |
