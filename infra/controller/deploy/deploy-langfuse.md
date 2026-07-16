# Deploy: Langfuse (observability stack)  —  controller

Prerequisite: controller provisioned (Docker present) per provision-controller.sh.
All steps run on the CONTROLLER unless marked MAC.

Langfuse v3 is a 6-container stack (web, worker, postgres, clickhouse, redis, minio).
We deploy from the **upstream compose + our overrides**, not a hand-written compose,
so we inherit upstream correctness and only override what's ours.

## 1. Get the repo on the box

    git config --global credential.helper store
    printf 'https://<user>:<PAT>@github.com\n' > /root/.git-credentials && chmod 600 /root/.git-credentials
    git clone https://github.com/zohaibtanwir/waterline.git /opt/waterline-repo
    cd /opt/waterline-repo/infra/controller/langfuse

## 2. Fetch the current upstream compose (it drifts — always fetch fresh)

    curl -fsSL https://raw.githubusercontent.com/langfuse/langfuse/main/docker-compose.yml -o docker-compose.deploy.yml

Then re-apply our three overrides to the fetched file:
- bind langfuse-web to the tailnet IP:  `sed -i 's|- 3000:3000|- "<TAILNET_IP>:3000:3000"|' docker-compose.deploy.yml`
- bind minio console to the tailnet IP: `sed -i 's|- 9090:9000|- "<TAILNET_IP>:9090:9000"|' docker-compose.deploy.yml`
- mount our ClickHouse memory cap into the clickhouse service volumes list:
  add `- ./clickhouse-memory.xml:/etc/clickhouse-server/config.d/memory.xml:ro`
Verify: `grep -nE '3000|9090|memory.xml' docker-compose.deploy.yml`

NOTE: the committed docker-compose.yml in this folder IS the upstream-derived,
overrides-applied file from a known-good deploy. Re-fetching (above) is only
needed when adopting a newer upstream; otherwise use the committed one directly.

## 3. Generate .env with FRESH secrets

Copy the template and fill it. Passwords must be internally consistent:
DATABASE_URL embeds POSTGRES_PASSWORD; the three S3 keys equal MINIO_ROOT_PASSWORD.

    cp .env.example .env && chmod 600 .env
    # generate values:
    #   openssl rand -hex 32   for each *_PASSWORD / CLICKHOUSE / ENCRYPTION_KEY
    #   openssl rand -base64 32 for NEXTAUTH_SECRET and SALT
    #   pk-lf-$(openssl rand -hex 16) and sk-lf-$(openssl rand -hex 16) for the two INIT project keys
    #   a login password for LANGFUSE_INIT_USER_PASSWORD
    # then edit .env: set DATABASE_URL password == POSTGRES_PASSWORD,
    #                 set the three S3 secret keys == MINIO_ROOT_PASSWORD,
    #                 set NEXTAUTH_URL=http://<TAILNET_IP>:3000

SAVE the two pk-lf-/sk-lf- keys — the gateway deploy needs them.
SAVE the INIT_USER email+password — that's your Langfuse UI login.

## 4. Bring it up

    docker compose -f docker-compose.deploy.yml up -d
    watch -n 3 'docker compose -f docker-compose.deploy.yml ps'

Wait for all six healthy/running (web is slowest — runs migrations on first boot).

## 5. Exit gate

    curl -s -o /dev/null -w "%{http_code}\n" http://<TAILNET_IP>:3000    # expect 200

From the Mac browser over Tailscale, open http://<TAILNET_IP>:3000 — log in with
the INIT_USER credentials; the Waterline org + Waterline Lab project should already
exist (auto-created by the init vars). Traces empty until the gateway logs to it.

## Known gotchas (see docs/failure-log.md)
- ClickHouse: only max_server_memory_usage is valid at server-config level;
  max_memory_usage there crash-loops the server (it's a user-profile setting).
- DATABASE_URL must carry the real password; upstream default is literally 'postgres'.
- If Postgres booted once with a wrong password, its volume is stuck on it —
  `docker compose down` then `docker volume rm langfuse_langfuse_postgres_data`,
  then `up` re-inits clean. (Only safe when the DB holds no real data.)
