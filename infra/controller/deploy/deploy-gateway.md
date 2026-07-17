# Deploy: LiteLLM gateway (model routing + virtual keys)  —  controller

Prerequisite: controller provisioned (Docker present); Langfuse already deployed
(the gateway logs to it). All steps run on the CONTROLLER unless marked.

The gateway holds the ONE real Anthropic key. Sandboxes never do — they receive
per-task virtual keys minted against this gateway. Image is PINNED to the
litellm-database variant (required for virtual keys + spend tracking).

## 1. Prerequisites in hand
- Real Anthropic key from the spend-limited `waterline` workspace (waterline-gateway).
- Langfuse project keys (pk-lf-/sk-lf-) — from the Langfuse .env
  (LANGFUSE_INIT_PROJECT_PUBLIC_KEY / _SECRET_KEY).
- Repo cloned to /opt/waterline-repo.

## 2. Generate .env with fresh secrets
    cd /opt/waterline-repo/infra/controller/gateway
    DBPASS=$(openssl rand -hex 32)
    cat > .env <<EOF
    ANTHROPIC_API_KEY=<waterline-gateway key>
    LITELLM_MASTER_KEY=sk-$(openssl rand -hex 24)
    LITELLM_SALT_KEY=$(openssl rand -hex 32)      # MUST persist across redeploys
    LITELLM_DB_PASSWORD=$DBPASS
    LITELLM_DATABASE_URL=postgresql://litellm:$DBPASS@litellm-db:5432/litellm
    LANGFUSE_PUBLIC_KEY=<pk-lf- from langfuse .env>
    LANGFUSE_SECRET_KEY=<sk-lf- from langfuse .env>
    EOF
    chmod 600 .env

Note LITELLM_SALT_KEY: rotating it invalidates every virtual key in flight —
generate once, keep forever.

## 3. Bring it up
    docker compose up -d          # pulls litellm-database:v1.89.0 + its postgres

## 4. Exit gate — health + full loop
    curl -s http://<TAILNET_IP>:4000/health/liveliness   # "I'm alive!"
    curl -s http://<TAILNET_IP>:4000/health/readiness     # {"status":"healthy","db":"connected"}

Prove the virtual-key lifecycle (mint -> call -> revoke):
    MASTER=$(grep LITELLM_MASTER_KEY .env | cut -d= -f2)
    # mint
    curl -s -X POST http://<TAILNET_IP>:4000/key/generate -H "Authorization: Bearer $MASTER" \
      -H "Content-Type: application/json" -d '{"key_alias":"smoke","max_budget":1,"duration":"1h"}'
    # call via a tier alias (verify = Haiku, cheapest)
    curl -s -X POST http://<TAILNET_IP>:4000/v1/chat/completions -H "Authorization: Bearer <vkey>" \
      -H "Content-Type: application/json" \
      -d '{"model":"verify","messages":[{"role":"user","content":"ping"}],"max_tokens":10}'
    # revoke
    curl -s -X POST http://<TAILNET_IP>:4000/key/delete -H "Authorization: Bearer $MASTER" \
      -H "Content-Type: application/json" -d '{"keys":["<vkey>"]}'

Confirm the call appears as a trace in Langfuse (Waterline Lab -> Tracing).

## 5. Wire the runner
- Sandbox-net -> controller egress is already all-ports (from L1), so sandboxes
  reach :4000 with no new iptables rule.
- On the runner host, place the gateway master key so sandbox-run.sh can mint keys:
    echo '<LITELLM_MASTER_KEY>' > /opt/waterline/gateway-master.key && chmod 600 ...
  (Host-only, never enters a sandbox. See KEY MODEL below.)
- Deploy sandbox-run.sh v0.3 (mints/revokes per-task virtual keys) from repo bin/.

## KEY MODEL (the security invariant)
- Real Anthropic key  -> CONTROLLER only (can spend real money)
- LiteLLM master key   -> controller + runner HOST (mints virtual keys; cannot
                          call Anthropic directly; NEVER enters a sandbox)
- Per-task virtual key -> SANDBOX only (budget-capped, revoked at destroy)

## Known gotchas
- Image tag: use litellm-database (not plain litellm) for DB features; pin a
  version (v1.89.0), never :latest / :main-stable (deprecating Sep 2026).
- Model name is NOT currently surfaced in Langfuse traces by LiteLLM's
  integration — observability gap noted for L8.
