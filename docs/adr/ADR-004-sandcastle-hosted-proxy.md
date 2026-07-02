# ADR-004 — Sandcastle hosted proxy baseline

**Status:** Accepted
**Date:** 2026-06-16
**Author:** Aaron Davis
**Deciders:** Maintainer (sole, at this stage)

---

## Context

Sandcastle GitHub Actions run on GitHub-hosted runners. Those runners cannot reach the local `shft` or `claude-code-copilot` proxy on the maintainer's workstation, so workflows that depend on `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` need a reachable proxy endpoint.

The proxy must preserve the existing security boundary: Actions should call an Anthropic-compatible LiteLLM endpoint backed by Copilot auth, without storing direct Anthropic keys in repository secrets or printing credential values in logs.

---

## Decision

Use a small **EC2 proxy-only host** that exposes `claude-code-copilot` through authenticated HTTPS while continuing to run Sandcastle workflows on GitHub-hosted runners.

Do not move Sandcastle to an EC2 self-hosted runner for this slice. Self-hosted runners would expand the trust boundary by placing repository checkout, workflow execution, and model proxy state on the same host. The selected baseline keeps GitHub Actions ephemeral and gives the EC2 instance one job: terminate TLS and forward authenticated model calls to the local proxy runtime.

---

## Security baseline

### Network access

- Public inbound `443/tcp` is allowed to the TLS reverse proxy so GitHub-hosted Actions can reach the endpoint.
- Direct access to the LiteLLM process port is not exposed publicly.
- `80/tcp` is either closed, redirected to HTTPS, or opened only as required for ACME HTTP-01 certificate issuance.
- GitHub-hosted runner IP allowlisting is not the baseline because runner egress ranges are broad and operationally brittle. Bearer auth, TLS, rate limiting, and narrow service exposure are the required controls.

### Admin access

- AWS Systems Manager Session Manager is the preferred admin path.
- Inbound SSH is disabled by default.
- If SSH is needed for break-glass recovery, it must be temporary, restricted to the maintainer's current IP, and removed after use.

### TLS strategy

- Caddy is the default TLS reverse proxy because it provides automatic certificate management and simple HTTPS redirect behavior.
- nginx with certbot or ALB with ACM are acceptable alternatives only if Caddy is unsuitable for the deployed host.
- The public endpoint stored in Actions secrets must be the HTTPS URL used as `LITELLM_BASE_URL`.

### Secret storage

- Store long-lived host secrets in AWS SSM Parameter Store `SecureString` or AWS Secrets Manager.
- The host may materialize a runtime `.env` file only during deployment with restrictive ownership and permissions.
- Secrets must not be written to user-data logs, shell history, AMI images, committed files, issue comments, or workflow logs.

### Proxy authentication

- `LITELLM_MASTER_KEY` is required for model calls and is passed by Sandcastle workflows as `ANTHROPIC_AUTH_TOKEN`.
- `/v1/messages` and other model endpoints must reject unauthenticated requests.
- Health/status endpoints may exist, but they must not expose model provider tokens, bearer tokens, request bodies, or sensitive configuration.

### Copilot OAuth cache

- Copilot OAuth is completed once on the host for the proxy runtime.
- The Copilot cache directory must persist across process and host restarts.
- Sandcastle Actions do not need `CLAUDE_CODE_OAUTH_TOKEN` in proxy mode. **Follow-up resolved (#134):** the hosted-proxy smoke now passes and no agent workflow references `CLAUDE_CODE_OAUTH_TOKEN` — every workflow derives `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` from `secrets.LITELLM_BASE_URL` / `secrets.LITELLM_MASTER_KEY`. The LiteLLM proxy env is therefore the canonical runner auth contract, and the `CLAUDE_CODE_OAUTH_TOKEN` compatibility contract is deprecated (no workflow dependency remains).

---

## Consequences

**Positive:**

- GitHub-hosted Actions can reach the model proxy without direct Anthropic credentials.
- Workflow execution stays on ephemeral GitHub infrastructure.
- The EC2 host has a narrow responsibility and can be locked down around HTTPS proxying and SSM administration.
- Copilot auth state persists on the host instead of being passed through each workflow run.

**Negative:**

- The public HTTPS endpoint is internet-reachable on `443/tcp`; security depends on strict bearer auth, TLS, rate limiting, and not exposing the underlying LiteLLM port.
- The maintainer must operate host patching, service supervision, certificate renewal, and secret rotation.

**Neutral:**

- This ADR selects the baseline only. Provisioning, deployment, HTTPS exposure, Actions secret wiring, and live Sandcastle smoke validation remain separate slices.
- The operational companion is the [Sandcastle hosted proxy EC2 runbook](../../shft/docs/hosted-proxy-ec2-runbook.md).

---

## Alternatives considered

**EC2 self-hosted runner plus local proxy:** Rejected for the baseline. It would make local proxy access simple, but it combines GitHub runner execution and persistent Copilot/proxy state on one host, increasing the blast radius of a workflow compromise.

**Keep using the workstation proxy:** Rejected. GitHub-hosted Actions cannot reliably reach a local workstation service, and exposing a workstation directly would weaken the private/public boundary.

**Direct Anthropic keys in Actions:** Rejected. The Sandcastle contract is proxy-first and should not require direct Anthropic credentials in repo secrets.
