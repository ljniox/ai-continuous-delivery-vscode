Super, on verrouille tout ça avec tes contraintes :

* **Supabase Projet A** : base de données/stockage de **l’instance Archon** (MCP) — sert de “mémoire/backlog/artefacts de contexte”.
* **Supabase Projet B** : **plan de contrôle** (ingestion d’e-mails, tables de suivi specs → sprints → runs, stockage des rapports, notifications).
* **E-mail** : boîte Gmail perso (réception des ordres de mission).
* **VPS dédié** : exécute le **runner GitHub Actions self-hosted**, **Claude Code** + **Qwen3-Coder via proxy**, **Playwright**, **Docker** (Archon), et scripts.
* **GitHub SaaS** : dépôt(s) + workflows.
* **Sans Coolify / n8n**.

Je te donne : ① l’architecture, ② les flux détaillés, ③ les templates (SQL, YAML, workflows, scripts), ④ un guide d’implémentation pas-à-pas.

---

# 1) Architecture détaillée

## 1.1. Composants

* **Archon (serveur MCP)** sur le VPS, connecté à **Supabase A** (DB + Storage). Claude Code s’y connecte en MCP pour lire/écrire backlog, notes, contextes. (MCP = standard d’échanges outils↔LLM.) ([Anthropic][1], [Anthropic][2], [GitHub][3])
* **Supabase B (control-plane)** :

  * **Edge Functions** pour recevoir les ordres (webhook), orchestrer les notifications. ([Supabase][4])
  * **Postgres + RLS** : tables `specs`, `sprints`, `runs`, `artifacts`, `status_events`.
  * **Storage** : `specs/` (cahiers des charges), `reports/` (JUnit, coverage, Lighthouse, logs). Liens **signés** pour envoyer par e-mail. ([Supabase][5])
* **Gmail perso** → **Gmail API** en mode *push* (Watch + Cloud Pub/Sub) vers une **Edge Function** de Supabase B (ou fallback *poller* cron sur le VPS). ([Google for Developers][6])
* **GitHub**

  * **Hosted runners** : optionnels pour des jobs légers (lint, docs). ([GitHub Docs][7])
  * **Self-hosted runner** (ton VPS) : jobs qui nécessitent Claude Code/Qwen/Playwright. ([GitHub Docs][8])
* **Agents de code**

  * **Claude Code CLI** pour planifier/implémenter (EPIC → Sprint → tâches) et committer. ([Anthropic][9])
  * **Qwen3-Coder** via le **Claude Code proxy API** pour exécuter/contre-tester/fixer (on “bascule” via variables d’env). ([Qwen][10], [AI Engineer Guide][11])
* **Tests** : **Playwright** (E2E) + unitaires (pytest). ([playwright.dev][12])

## 1.2. Répartition Projet A / Projet B

* **Supabase A (Archon)**

  * DB : tables internalisées d’Archon (pages, notes, backlog), éventuel index vectoriel.
  * Storage : documents de référence (PDF specs, maquettes).
  * Archon tourne sur **Docker** (VPS), point MCP exposé en `http://localhost:8080`.

* **Supabase B (Orchestration)**

  * DB : suivi structuré **exécutable** (specs→sprints→runs).
  * Storage : sources *spec.yaml* et **artefacts CI** (rapports).
  * Edge Functions : `ingest_email`, `notify_report`.

---

# 2) Flux entre les entités

## 2.1. Ingestion de l’ordre de mission (e-mail)

**Option A (recommandé)** — *Gmail Push (Watch + Pub/Sub)*

1. Gmail → **Watch** (Pub/Sub) → Push HTTP vers `Edge Function ingest_email` (Supabase B). ([Google for Developers][6])
2. `ingest_email` extrait le contenu/attachements, écrit le **fichier `specs/<id>.yaml`** dans **Storage B**, insère en DB `specs(...)`, publie `status_events('SPEC_RECEIVED')`. ([Supabase][4])
3. `ingest_email` déclenche **GitHub workflow** (événement `repository_dispatch`) avec un **lien signé** vers la spec. ([Supabase][5])

**Option B (fallback)** — *Poller sur VPS*
Un service cron lit Gmail API périodiquement, pousse la spec vers Storage B et appelle l’API GitHub. (Moins réactif, pas de Pub/Sub.)

## 2.2. Planification & code (runner self-hosted sur VPS)

4. Job GitHub “**plan\_build\_test**” (labels `self-hosted, linux, x64`) s’exécute sur le VPS. ([GitHub Docs][8])
5. Le job télécharge `spec.yaml` via **URL signée Supabase B**. ([Supabase][5])
6. Démarre **Archon (MCP)** (Docker). Claude Code s’y connecte :

   * lit/écrit backlog, découpe **EPIC → SPRINT → manifest.yaml**, prépare branches `feature/Sx/*`, init l’ossature (MVP), commit & push. (MCP & Claude Code) ([Anthropic][1])

## 2.3. Tests & DoD

7. **Qwen3-Coder via proxy** (variables `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`) lance **tests** (pytest, Playwright), génère **rapports** JUnit/coverage/Lighthouse. ([Qwen][10])
8. Le job uploade les rapports dans **Storage B** et écrit `runs`, `artifacts`, `status_events('TESTS_PASSED'|FAILED)`. (Supabase B Storage + DB) ([Supabase][5])
9. Un script “DoD check” lit le **résumé machine-lisible** et décide **merge** de la PR (ou ouvre issue de corrections).

## 2.4. Notification

10. Le job appelle **`notify_report`** (Edge Function Supabase B) → envoie **e-mail récap** (à l’adresse Gmail) avec **liens signés** vers les artefacts. ([Supabase][4])

---

# 3) Templates d’artefacts

## 3.1. Schéma SQL (Supabase B)

```sql
-- schemas/control_plane.sql
create table specs (
  id uuid primary key default gen_random_uuid(),
  repo text not null,
  branch text not null,
  storage_path text not null,
  sha text,
  created_at timestamptz default now(),
  created_by text
);

create table sprints (
  id uuid primary key default gen_random_uuid(),
  spec_id uuid references specs(id) on delete cascade,
  label text not null,      -- e.g. "S1"
  dod_json jsonb not null,  -- critères exécutables
  state text not null default 'PLANNED', -- PLANNED/RUNNING/DONE/FAILED
  created_at timestamptz default now()
);

create table runs (
  id uuid primary key default gen_random_uuid(),
  sprint_id uuid references sprints(id) on delete cascade,
  ci_run_id text,
  started_at timestamptz default now(),
  finished_at timestamptz,
  result text,              -- PASSED/FAILED
  summary_json jsonb
);

create table artifacts (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references runs(id) on delete cascade,
  kind text,                -- junit|coverage|lighthouse|logs
  storage_path text not null,
  size bigint,
  created_at timestamptz default now()
);

create table status_events (
  id bigserial primary key,
  run_id uuid,
  phase text,               -- SPEC_RECEIVED|PLANNING|BUILD|TESTS_PASSED|FAILED|MERGED
  message text,
  ts timestamptz default now()
);
```

> Activer RLS et autoriser **insert** seulement via *service role* (Edge Functions / CI).

## 3.2. Spec YAML (déposée dans `specs/…` de Storage B)

```yaml
meta:
  project: my-app
  repo: org/my-app
  requester_email: "you@gmail.com"
planning:
  epics:
    - id: E1
      title: "MVP Auth & Catalogue"
      sprints:
        - id: S1
          goals: ["Ossature FastAPI + Jinja + Postgres", "Liste catalogue"]
          user_stories:
            - id: US1
              as: "visitor"
              want: "voir la liste"
              so_that: "comprendre l'offre"
              acceptance:
                - "E2E: e2e/specs/catalogue.spec.ts"
          dod:
            coverage_min: 0.80
            e2e_pass: true
            lighthouse_min: 85
runtime:
  stack:
    backend: "Python 3.11 + FastAPI + Jinja2"
    db: "Postgres 15"
tests:
  e2e: "Playwright"
  unit: "pytest"
policies:
  coding_standards: "ruff, mypy strict, black"
  branch: "feature/S1/*"
```

## 3.3. Manifeste Sprint généré par Claude Code (commit dans repo)

```yaml
sprint_id: S1
tasks:
  - id: S1-T1
    type: scaffold
    desc: "Init FastAPI + templates Jinja + Dockerfile"
    done_when:
      - "pytest -q passes"
      - "ruff . returns 0"
  - id: S1-T2
    type: feature
    desc: "Endpoint /items + template catalogue"
    tests:
      unit: ["tests/unit/test_items.py"]
      e2e:  ["e2e/specs/catalogue.spec.ts"]
artifact_contract:
  junit: "artifacts/junit.xml"
  coverage: "artifacts/coverage.xml"
  lighthouse: "artifacts/lh.json"
```

## 3.4. Workflow GitHub (job sur runner self-hosted)

`.github/workflows/sprint.yml`

```yaml
name: Sprint Runner
on:
  repository_dispatch:
    types: [spec_ingested]
  workflow_dispatch:

jobs:
  plan_build_test:
    runs-on: [self-hosted, linux, x64]  # VPS
    env:
      SUPABASE_URL: ${{ secrets.SUPABASE_B_URL }}
      SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_B_SERVICE_ROLE }}
      SPEC_SIGNED_URL: ${{ github.event.client_payload.spec_url }}
      ARCHON_URL: http://localhost:8080
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python & Node
        uses: actions/setup-python@v5
        with: { python-version: "3.11" }
      - uses: actions/setup-node@v4
        with: { node-version: "20" }

      - name: Start Archon (Docker)
        run: docker compose -f ops/archon/docker-compose.yml up -d

      - name: Fetch spec
        run: curl -L "$SPEC_SIGNED_URL" -o spec.yaml

      - name: Claude Code — planifier & coder
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: bash scripts/cc_plan_and_code.sh

      - name: Qwen — exécuter les tests (via proxy Claude Code)
        env:
          ANTHROPIC_BASE_URL: https://dashscope-intl.aliyuncs.com/api/v2/apps/claude-code-proxy
          ANTHROPIC_AUTH_TOKEN: ${{ secrets.DASHSCOPE_API_KEY }}
        run: bash scripts/qwen_run_tests.sh

      - name: Upload artifacts -> Supabase B
        run: python ops/upload_artifacts.py

      - name: DoD gate (merge si OK)
        run: python ops/dod_gate.py

      - name: Notify report
        run: curl -X POST "$SUPABASE_URL/functions/v1/notify_report" \
             -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
             -H "Content-Type: application/json" \
             -d @artifacts/summary.json
```

> Claude Code CLI & “non-interactive” usage/SDK existent côté Anthropic. ([Anthropic][13])
> Qwen3-Coder via **Claude Code proxy API** : variables d’env ci-dessus. ([Qwen][10])

## 3.5. Scripts côté repo

`scripts/cc_plan_and_code.sh`

```bash
set -euo pipefail
# Connexion MCP -> Archon
export CLAUDE_CODE_MCP_SERVER_URL="$ARCHON_URL"

# 1) Lire spec.yaml, pousser vers Archon (contexte)
claude-code --project . --run 'read:spec.yaml -> plan:epic->sprint -> write:sprints/S1/manifest.yaml'

# 2) Générer ossature + commits
claude-code --project . --run 'scaffold:mvp -> create_branch:feature/S1/init -> commit_push:"chore(scaffold): init MVP"'
```

`scripts/qwen_run_tests.sh`

```bash
set -euo pipefail
# Ici Claude Code parle au proxy Qwen3-Coder via env ANTHROPIC_BASE_URL/TOKEN
npm ci
npx playwright install --with-deps
pytest -q || true
npx playwright test || true

# Regrouper rapports
mkdir -p artifacts
# (exemples) copier junit/coverage/lh
```

## 3.6. Playwright (E2E minimal)

`e2e/specs/catalogue.spec.ts`

```ts
import { test, expect } from "@playwright/test";

test("liste catalogue visible", async ({ page }) => {
  await page.goto(process.env.APP_URL || "http://localhost:8000");
  await expect(page.getByRole("heading", { name: /catalogue/i })).toBeVisible();
});
```

([playwright.dev][14])

## 3.7. Résumé machine-lisible (consommé par DoD gate)

`artifacts/summary.json`

```json
{
  "coverage": 0.86,
  "unit_pass": true,
  "e2e_pass": true,
  "lighthouse": 89,
  "notes": "OK DoD S1"
}
```

## 3.8. Edge Functions (Supabase B)

`functions/ingest_email/index.ts`

```ts
import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js";

serve(async (req) => {
  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const payload = await req.json(); // message Pub/Sub -> Gmail push
  const { subject, body, attachments } = parseGmailPush(payload);

  const path = `specs/${crypto.randomUUID()}.yaml`;
  await supa.storage.from("automation").upload(path, new Blob([body]), { contentType: "text/yaml" });

  const { data: spec } = await supa.from("specs").insert({
    repo: "org/my-app", branch: "spec/auto", storage_path: path, created_by: "gmail-push"
  }).select().single();

  const { data: url } = await supa.storage.from("automation").createSignedUrl(path, 86400);
  await emitStatus(supa, null, "SPEC_RECEIVED", `Spec ${spec?.id} déposé`);

  // Déclenche le workflow GitHub
  await fetch("https://api.github.com/repos/org/my-app/dispatches", {
    method: "POST",
    headers: { "Authorization": `Bearer ${Deno.env.get("GITHUB_TOKEN")!}`, "Accept": "application/vnd.github+json" },
    body: JSON.stringify({ event_type: "spec_ingested", client_payload: { spec_url: url?.signedUrl } })
  });

  return new Response("OK");
});
```

> Edge Functions (Deno) & Storage URLs signées. ([Supabase][4])

`functions/notify_report/index.ts`

```ts
import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js";

serve(async (req) => {
  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const summary = await req.json(); // summary.json
  // Générer e-mail (via provider SMTP/API de ton choix)
  await sendEmail({
    to: summary.requester_email,
    subject: `Sprint ${summary.sprint} — ${summary.result}`,
    html: renderHtml(summary) // inclut des liens signés vers artifacts
  });
  return new Response("OK");
});
```

## 3.9. Archon (Docker Compose – Projet A)

`ops/archon/docker-compose.yml`

```yaml
services:
  archon:
    image: ghcr.io/your-org/archon:latest
    ports: ["8080:8080"]
    environment:
      SUPABASE_URL: ${SUPABASE_A_URL}
      SUPABASE_SERVICE_KEY: ${SUPABASE_A_SERVICE_ROLE}
      ARCHON_STORAGE: /data
    volumes:
      - archon_data:/data
volumes:
  archon_data: {}
```

## 3.10. Services système (VPS)

**Runner GitHub self-hosted** (extrait) ([GitHub Docs][8])

```
# useradd -m actions
# sudo -u actions ./config.sh --url https://github.com/org/repo --token ****
# sudo systemctl enable --now actions.runner.org-repo.service
```

---

# 4) Guide d’implémentation pas-à-pas

### Étape 0 — Pré-requis

* Domaine HTTPS (Edge Functions publiques), Node 20, Python 3.11, Docker, Git.
* Comptes : GitHub, Supabase (2 projets), Anthropic (clé), Alibaba DashScope (clé Qwen).
* Installer **Claude Code** (`npm i -g @anthropic-ai/claude-code`). ([Anthropic][15])
* Installer **Playwright** et dépendances (CI). ([playwright.dev][12])

### Étape 1 — Supabase Projet B (control-plane)

1. Crée le **bucket Storage** `automation` (dossiers `specs/`, `reports/`).
2. Applique le **SQL** ci-dessus ; active **RLS** (politiques : insert via service role).
3. Déploie **Edge Functions** `ingest_email`, `notify_report`. ([Supabase][4])
4. Sauvegarde `SUPABASE_B_URL`, `SUPABASE_B_SERVICE_ROLE` pour GitHub Secrets.
5. Vérifie la génération de **signed URLs** côté tests. ([Supabase][5])

### Étape 2 — Gmail → Supabase B

* **Option Push** (reco) : configure `users.watch` (Gmail API) vers un **topic Pub/Sub** qui *push* sur `ingest_email` (Edge). ([Google for Developers][6])
* **Option Poll** : service cron sur VPS qui lit l’INBOX et POST sur `ingest_email`.

### Étape 3 — GitHub

1. Crée le repo (ou utilise le tien).
2. Ajoute **GitHub Secrets** :

   * `SUPABASE_B_URL`, `SUPABASE_B_SERVICE_ROLE`, `GITHUB_TOKEN` (Fine-grained),
   * `ANTHROPIC_API_KEY`, `DASHSCOPE_API_KEY`.
3. Ajoute le **workflow** `.github/workflows/sprint.yml`.
4. Sur le **VPS**, installe le **runner self-hosted** et assigne les labels. ([GitHub Docs][8])

### Étape 4 — VPS (exécutions)

1. Installe **Claude Code**, **Node 20**, **Python 3.11**, **Docker**.
2. Place `ops/archon/docker-compose.yml` (Projet A relié) et variables `SUPABASE_A_*`.
3. Teste `docker compose up -d` (Archon écoute `:8080`).

### Étape 5 — Intégration agents

1. **Claude Code** : confirmé via `claude-code --help` (CLI/SDK). ([Anthropic][13])
2. **Qwen3-Coder** : activer le **proxy Claude Code** (via `ANTHROPIC_BASE_URL` & token DashScope) dans le job “tests”. ([Qwen][10])

### Étape 6 — Tests E2E & DoD

1. Ajoute **pytest**, **Playwright** (+ `npx playwright install --with-deps`). ([playwright.dev][12])
2. Ajoute `e2e/specs/*.spec.ts` (exemple fourni) et règles **DoD** (coverage, Lighthouse…).
3. Implémente `ops/dod_gate.py` qui lit `artifacts/summary.json` et décide merge/issue.

### Étape 7 — Chaîne complète

1. Envoie un e-mail “ordre de mission” → `ingest_email` dépose `spec.yaml` + déclenche le workflow.
2. Le job planifie (Archon+Claude Code), code, teste (Qwen/Playwright), publie artefacts (Storage B signed URLs), **notifie** par e-mail.
3. Sprint suivant : répéter tant que `planning.epics[].sprints[]` reste à traiter.

---

## Remarques & bonnes pratiques

* **MCP** : standardise la connexion **Claude Code ↔ Archon** (sources/outils). ([Anthropic][1], [Anthropic][2])
* **Sécurité** :

  * Secrets uniquement en **GitHub Secrets** / variables d’env du runner.
  * **Service Role** Supabase utilisé seulement côté **Edge/CI**.
* **Observabilité** : stocke et **partage par URLs signées** (expiration 24–72h). ([Supabase][5])
* **Runners** : isole les jobs lourds sur **self-hosted** (VPS) ; le reste peut tourner sur GitHub-hosted. ([GitHub Docs][8])
* **Qwen mix** : utile pour contre-tester à coût réduit via le **proxy** intégré à Claude Code. ([Qwen][10])

---

Si tu veux, je peux te **générer un dépôt squelette** conforme (répertoires `ops/`, `functions/`, `scripts/`, `e2e/`, SQL Supabase B, workflows, docker-compose Archon A) — tu n’auras qu’à coller tes clés et pousser.

[1]: https://docs.anthropic.com/en/docs/mcp?utm_source=chatgpt.com "Model Context Protocol (MCP)"
[2]: https://www.anthropic.com/news/model-context-protocol?utm_source=chatgpt.com "Introducing the Model Context Protocol"
[3]: https://github.com/modelcontextprotocol?utm_source=chatgpt.com "Model Context Protocol"
[4]: https://supabase.com/docs/guides/functions?utm_source=chatgpt.com "Edge Functions | Supabase Docs"
[5]: https://supabase.com/docs/reference/javascript/storage-from-createsignedurl?utm_source=chatgpt.com "JavaScript: Create a signed URL"
[6]: https://developers.google.com/workspace/gmail/api/guides/push?utm_source=chatgpt.com "Push Notifications | Gmail"
[7]: https://docs.github.com/actions/using-github-hosted-runners/about-github-hosted-runners?utm_source=chatgpt.com "GitHub-hosted runners"
[8]: https://docs.github.com/actions/hosting-your-own-runners?utm_source=chatgpt.com "Self-hosted runners"
[9]: https://docs.anthropic.com/en/docs/claude-code/overview?utm_source=chatgpt.com "Claude Code overview"
[10]: https://qwenlm.github.io/blog/qwen3-coder/?utm_source=chatgpt.com "Qwen3-Coder: Agentic Coding in the World | Qwen"
[11]: https://aiengineerguide.com/blog/claude-code-qwen3-coder/?utm_source=chatgpt.com "How to use Claude Code with Qwen3 Coder"
[12]: https://playwright.dev/?utm_source=chatgpt.com "Playwright: Fast and reliable end-to-end testing for modern ..."
[13]: https://docs.anthropic.com/en/docs/claude-code/cli-reference?utm_source=chatgpt.com "CLI reference"
[14]: https://playwright.dev/docs/writing-tests?utm_source=chatgpt.com "Writing tests"
[15]: https://docs.anthropic.com/en/docs/claude-code/quickstart?utm_source=chatgpt.com "Quickstart - Claude Code"

-- -- -- 
Prompt : Variante: j’utilise Claude Code et Qwen CLI en mode souscription
-- -- -- 

Parfait. En **mode souscription** (Claude Pro/Max + Qwen côté DashScope), on garde la même mécanique globale — on ajuste surtout **l’authentification**, **les limites** et **la gestion des secrets**.

Voici : 1) ce qui change, 2) l’architecture mise à jour, 3) les flows entre toutes les briques, 4) les templates (env, workflow, scripts), 5) le pas-à-pas d’implémentation, + 6) quelques garde-fous coûts/quotas.

---

# 1) Ce qui change en “souscription”

* **Claude Code**

  * Tu n’utilises pas d’API key “console PAYG” dans tes jobs : tu **te connectes à la CLI avec ton abonnement** (Pro / Max) via `/login`. Sur un runner, ça se fait **une fois** (session persistée dans le `$HOME` du compte système qui exécute les jobs). Ensuite, la CLI use le token d’abonnement pour toutes les commandes. ([Anthropic][1], [Centre d'Aide Anthropic][2])
  * Plans & limites (Pro / Max) : Pro inclut Claude Code, Max a des capacités supérieures (tokens, modèles). ([Anthropic][3])

* **Qwen CLI (Qwen3-Coder)**

  * Côté Alibaba **DashScope** c’est essentiellement **au jeton (PAYG)** même si tu “t’abonnes” à l’outil côté workflow ; tu fournis un **access token DashScope** (ou utilises le **proxy “Claude Code proxy API”** si tu passes par Claude Code comme client pivot). ([AlibabaCloud][4], [Qwen][5])

> NB : “Souscription” = siège Pro/Max pour Claude Code (CLI) ; pour Qwen, l’offre principale reste facturation à l’usage côté API (DashScope). ([Medium][6])

---

# 2) Architecture (mise à jour)

* **Supabase A** : backend Archon (MCP) — inchangé.
* **Supabase B** : control-plane (specs/sprints/runs + Storage + Edge Functions) — inchangé.
* **Gmail perso** → **Edge Function** Supabase B (push Pub/Sub ou fallback cron) — inchangé.
* **GitHub SaaS** : dépôt + workflows.
* **VPS dédié** :

  * **Runner GitHub self-hosted** (exécute les jobs lourds)
  * **Archon (Docker)** relié à Supabase A
  * **Claude Code (CLI)** connecté **une fois** à **ta souscription** (session persistée)
  * **Qwen (via DashScope)** accessible soit **directement** (Qwen CLI/API), soit **indirectement** via **Claude Code proxy API** (variables d’env). ([DataCamp][7])
* **MCP** : standard d’interconnexion agents↔outils (Archon, etc.). ([Model Context Protocol][8], [Anthropic][9])

---

# 3) Flows entre entités

1. **Email → Ingestion** : Gmail push → `functions/ingest_email` (Supabase B) → enregistre `spec.yaml` (Storage B) + insert `specs` + déclenche GitHub (`repository_dispatch` avec URL signée). ([Model Context Protocol][8], [Anthropic][3], [Centre d'Aide Anthropic][2])
2. **Planification** : Job “plan\_build\_test” (runner VPS) → télécharge `spec.yaml` → démarre **Archon** (Docker) → **Claude Code** (connecté à ton **compte Pro/Max**) se branche en **MCP** sur Archon, découpe EPIC→Sprint, génère ossature, commit & push. ([Anthropic][1])
3. **Tests/DoD** : même job → lance **Qwen** (via DashScope ou via **Claude Code proxy API**) pour exécuter unitaires + Playwright E2E → publie artefacts (Storage B) → met à jour `runs`, `artifacts`, `status_events`. ([AlibabaCloud][4])
4. **Gate DoD & Merge** : script lit `summary.json`, décide merge/PR, ouvre issue si échec.
5. **Rapport** : `functions/notify_report` (Supabase B) envoie l’e-mail avec **liens signés** vers les rapports. ([Anthropic][3])

---

# 4) Templates utiles

## 4.1. Variables d’environnement (Runner VPS)

`/etc/runner/env` (chargé par systemd ou au début du job) :

```
# Supabase B (control-plane)
SUPABASE_B_URL=...
SUPABASE_B_SERVICE_ROLE=...

# Archon -> Supabase A
SUPABASE_A_URL=...
SUPABASE_A_SERVICE_ROLE=...

# GitHub dispatch
GITHUB_TOKEN=...

# Qwen (DashScope) – si usage direct API
DASHSCOPE_API_KEY=...

# Option: Proxy Claude Code -> Qwen
ANTHROPIC_BASE_URL=https://dashscope-intl.aliyuncs.com/api/v2/apps/claude-code-proxy
ANTHROPIC_AUTH_TOKEN=$DASHSCOPE_API_KEY
```

> (Pas d’API key Anthropic si tu es **loggé** à ta souscription sur la machine.)

## 4.2. Initialisation Claude Code (sur le VPS, **une fois**)

```bash
# Installer la CLI native (Anthropic)
curl -fsSL https://claude.ai/install.sh | bash
# Login à TA souscription (ouvre un device code / URL)
claude /login
# (suivre les instructions – la session est persistée sur le $HOME du user runner)
```

Docs installation & usage souscription. ([Anthropic][1])

## 4.3. Workflow GitHub (extrait mis à jour)

`.github/workflows/sprint.yml`

```yaml
name: Sprint Runner
on:
  repository_dispatch:
    types: [spec_ingested]
  workflow_dispatch:

jobs:
  plan_build_test:
    runs-on: [self-hosted, linux, x64]
    env:
      SUPABASE_URL: ${{ secrets.SUPABASE_B_URL }}
      SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_B_SERVICE_ROLE }}
      SPEC_SIGNED_URL: ${{ github.event.client_payload.spec_url }}
      ARCHON_URL: http://localhost:8080

      # Qwen via proxy (si utilisé)
      ANTHROPIC_BASE_URL: https://dashscope-intl.aliyuncs.com/api/v2/apps/claude-code-proxy
      ANTHROPIC_AUTH_TOKEN: ${{ secrets.DASHSCOPE_API_KEY }}
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python & Node
        uses: actions/setup-python@v5
        with: { python-version: "3.11" }
      - uses: actions/setup-node@v4
        with: { node-version: "20" }

      - name: Start Archon
        run: docker compose -f ops/archon/docker-compose.yml up -d

      - name: Fetch spec
        run: curl -L "$SPEC_SIGNED_URL" -o spec.yaml

      - name: Claude Code — planifier & coder (abonnement)
        run: bash scripts/cc_plan_and_code.sh

      - name: Qwen — tests (via DashScope ou proxy)
        run: bash scripts/qwen_run_tests.sh

      - name: Upload artifacts -> Supabase B
        run: python ops/upload_artifacts.py

      - name: DoD gate (merge si OK)
        run: python ops/dod_gate.py

      - name: Notify report
        run: curl -X POST "$SUPABASE_URL/functions/v1/notify_report" \
             -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
             -H "Content-Type: application/json" \
             -d @artifacts/summary.json
```

## 4.4. Scripts (identiques, mais **sans** ANTHROPIC\_API\_KEY)

`scripts/cc_plan_and_code.sh`

```bash
set -euo pipefail
# Claude Code utilisera la session souscription déjà enregistrée sur le VPS
export CLAUDE_CODE_MCP_SERVER_URL="$ARCHON_URL"

claude --version

# 1) Planifier depuis spec.yaml via Archon MCP
claude run 'read:spec.yaml -> plan:epic->sprint -> write:sprints/S1/manifest.yaml'

# 2) Générer l’ossature + commits
claude run 'scaffold:mvp -> create_branch:feature/S1/init -> commit_push:"chore(scaffold): init MVP"'
```

> Commandes illustratives : suis la doc “Quickstart/Overview” pour les verbes exacts disponibles dans ta version. ([Anthropic][10])

`scripts/qwen_run_tests.sh`

```bash
set -euo pipefail
# Si tu passes par le proxy Claude Code -> Qwen, les env ANTHROPIC_BASE_URL/TOKEN suffisent
# Sinon, utilise directement la CLI/API Qwen/DashScope pour lancer tes scripts

npm ci
npx playwright install --with-deps
pytest -q || true
npx playwright test || true

mkdir -p artifacts
# copie des rapports junit/coverage/lh vers ./artifacts
```

## 4.5. Compose Archon (Projet A) — inchangé

```yaml
services:
  archon:
    image: ghcr.io/your-org/archon:latest
    ports: ["8080:8080"]
    environment:
      SUPABASE_URL: ${SUPABASE_A_URL}
      SUPABASE_SERVICE_KEY: ${SUPABASE_A_SERVICE_ROLE}
      ARCHON_STORAGE: /data
    volumes:
      - archon_data:/data
volumes:
  archon_data: {}
```

---

# 5) Guide pas-à-pas

1. **Supabase B**

   * Crée bucket `automation` (prefix `specs/`, `reports/`).
   * Applique le SQL (tables `specs/sprints/runs/artifacts/status_events`).
   * Déploie `functions/ingest_email` et `notify_report`. Teste **URL signées**. ([Model Context Protocol][8], [Anthropic][3])

2. **Gmail → Push**

   * Active **Gmail Watch** vers Pub/Sub, configure le push HTTP → `ingest_email`. (Ou cron fallback.) ([Centre d'Aide Anthropic][2])

3. **GitHub**

   * Ajoute secrets : `SUPABASE_B_URL`, `SUPABASE_B_SERVICE_ROLE`, `DASHSCOPE_API_KEY`.
   * Ajoute le workflow `.github/workflows/sprint.yml`.

4. **VPS / Runner**

   * Installe Docker, Node 20, Python 3.11.
   * Installe **Claude Code** (script officiel), **login** à ta **souscription** (`claude /login`) **en tant que l’utilisateur système** du runner → session persistée. ([Anthropic][1])
   * Déploie Archon (Compose) + variables Supabase A.

5. **Tests**

   * Pousse une spec (email) → Edge Function dépose `spec.yaml` et déclenche `repository_dispatch`.
   * Observe le job : planification (MCP Archon), code, tests Qwen/Playwright, artefacts → Storage B, e-mail résumé.

6. **Durcir**

   * Ajoute un **DoD gate** strict (coverage, E2E, Lighthouse).
   * Ajoute **quotas** et garde-fous (timeouts, taille contexte).

---

# 6) Coûts, limites, sécurité

* **Claude Code (abonnement)** : Pro inclut Claude Code ; Max est plus généreux (contexte, modèles). Vérifie ce qui est inclus et les limites d’usage de ta formule. ([Anthropic][3])
* **Qwen (DashScope)** : facturation **par token** (prix variables selon *qwen3-coder-flash/plus* et paliers). Active **context-cache** si dispo pour réduire le coût d’input. ([AlibabaCloud][4])
* **Sécurité** :

  * La **connexion Claude Code** sur VPS confère des droits “compte” : isole l’utilisateur `actions` (pas de sudo), réseau restreint, volumes éphémères.
  * Secrets GitHub uniquement côté **Actions** / **Edge Functions** (service role).
  * **MCP** : n’expose Archon qu’en local (localhost) si possible. ([Model Context Protocol][8])

---

## TL;DR

* Tu **loggues** Claude Code **une fois** sur le runner → tous les jobs utilisent la **souscription** (pas d’API key Anthropic dans les workflows). ([Centre d'Aide Anthropic][2])
* **Qwen** reste **via DashScope** (token au job) ou via **proxy Claude Code**. ([AlibabaCloud][4])
* Le reste (Supabase A/B, Gmail push, Archon MCP, Playwright) ne change pas.
  Si tu veux, je te fournis un **package d’initialisation** (scripts + unit-files systemd + README) adapté à ce mode “souscription only”.

[1]: https://docs.anthropic.com/en/docs/claude-code/setup?utm_source=chatgpt.com "Set up Claude Code"
[2]: https://support.anthropic.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan?utm_source=chatgpt.com "Using Claude Code with your Pro or Max plan"
[3]: https://www.anthropic.com/claude-code?utm_source=chatgpt.com "Claude Code: Deep coding at terminal velocity ..."
[4]: https://www.alibabacloud.com/help/en/model-studio/qwen-coder?utm_source=chatgpt.com "Alibaba Cloud Model Studio:Code capabilities (Qwen-Coder)"
[5]: https://qwenlm.github.io/blog/qwen3-coder/?utm_source=chatgpt.com "Qwen3-Coder: Agentic Coding in the World | Qwen"
[6]: https://medium.com/%40fairjmflyer/qwen3-coder-explained-performance-analysis-pricing-insights-and-getting-started-guide-301a7a4b137b?utm_source=chatgpt.com "Qwen3-Coder Explained: Performance Analysis, Pricing Insights ..."
[7]: https://www.datacamp.com/tutorial/qwen-code?utm_source=chatgpt.com "Qwen Code CLI: A Guide With Examples"
[8]: https://modelcontextprotocol.io/?utm_source=chatgpt.com "Model Context Protocol: Introduction"
[9]: https://www.anthropic.com/news/model-context-protocol?utm_source=chatgpt.com "Introducing the Model Context Protocol"
[10]: https://docs.anthropic.com/en/docs/claude-code/quickstart?utm_source=chatgpt.com "Quickstart - Claude Code"
