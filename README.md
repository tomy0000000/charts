# charts

Helm charts, published to `https://charts.tomy.me`.

```bash
helm repo add tomy0000000 https://charts.tomy.me
helm search repo tomy0000000
```

| Chart                    | What it runs                                                        |
| ------------------------ | ------------------------------------------------------------------- |
| [email-mcp](email-mcp/)  | mcp-email-server as a remote MCP server for a mailcow mailbox       |

## Releasing

Bump `version` in the chart's `Chart.yaml` and push to `main`. The workflow
(`.github/workflows/deploy.yml`) lints and packages every chart, creates a
GitHub Release `<chart>-<version>` with the `.tgz` attached for each version
that has none yet, then rebuilds the site from every release and deploys it
to GitHub Pages. Releases are the store, the site is a mirror of them, so a
lost site comes back on the next push.

A version that already has a release is never re-uploaded, so a change to a
published chart always needs a bump. Pull requests run the same lint and
package steps without releasing or deploying.
