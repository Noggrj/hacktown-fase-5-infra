# fiapx-infra

📐 **[Documentação da arquitetura completa](docs/ARQUITETURA.md)** —
diagrama, fluxo de eventos, decisões e o mapeamento de cada requisito do
desafio pra como foi atendido.

Infraestrutura AWS (Terraform) + Kafka/Redis/Prometheus/Ingress (Helm) do
sistema de processamento de vídeos FIAP X — Hackathon SOAT (Fase 5).
Provisiona o que os 4 microsserviços (
[`fiapx-auth-service`](https://github.com/noggrj/hacktown-fase-5-auth-service),
[`fiapx-video-service`](https://github.com/noggrj/hacktown-fase-5-video-service),
[`fiapx-processing-worker`](https://github.com/noggrj/hacktown-fase-5-processing-worker),
[`fiapx-notification-service`](https://github.com/noggrj/hacktown-fase-5-notification-service))
precisam pra rodar em produção.

## O que este repo provisiona

| Via | Recurso |
|---|---|
| Terraform | VPC, cluster EKS + node group, 2× RDS PostgreSQL (Auth, Video), 5× ECR (4 serviços + frontend), bucket S3 (vídeos), namespace `fiapx` |
| Helm (`terraform/helm.tf`) | Ingress NGINX, Kafka self-hosted (Bitnami, KRaft, 1 broker), Redis (Bitnami, standalone), kube-prometheus-stack (Prometheus + Grafana) |
| `kubectl` (CI, fora do Terraform) | Regras de `Ingress` (`k8s/ingress/rules.yaml`), Jobs de migration do Postgres |

Processing Worker e Notification Service não têm RDS — usam o Redis
compartilhado pra idempotência (ver README de cada um).

## Por que Terraform + Helm no mesmo repo (diferente da Fase 4)?

Na Fase 4 (`autorepair-infra-k8s`/`autorepair-infra-db`) a infra ficou em
2 repositórios porque RDS dependia de outputs do cluster via
`terraform_remote_state`. Aqui, dado o prazo menor da Fase 5, tudo cabe
num state só — menos overhead de repositório, sem perda de rigor (RDS
continua com security group, subnet group e credenciais próprios por
serviço).

## Decisões que valem registrar

- **Kafka/Redis via chart Bitnami** — mesmo catálogo já usado com sucesso
  pra RabbitMQ em `autorepair-infra-k8s` na Fase 4.
- **`LabRole` para EKS/RDS** — contas AWS Academy `voclabs` não permitem
  criar roles IAM novas; reaproveita a role pré-existente, mesma
  abordagem já validada na Fase 4.
- **`deletion_protection=false` no RDS** — essa infra tem vida curta
  (subir, gravar o vídeo de apresentação, destruir); manter proteção
  ligada só adicionaria um passo manual de "desprotege antes de destruir"
  a cada ciclo, sem nada de fato valioso pra proteger.
- **Prometheus honra as annotations `prometheus.io/scrape`** já presentes
  em cada `k8s/base/deployment.yaml` via um `additionalScrapeConfigs`
  (`k8s/observability/prometheus-values.yaml`) — evita precisar de um
  `ServiceMonitor` (CRD) por serviço.
- **Ingress sem rewrite** — cada serviço já registra suas rotas com o
  prefixo incluso (`/auth/login`, `/videos/{id}`), então o Ingress só
  encaminha o path original.

## Pré-requisitos

- Terraform ≥ 1.5, AWS CLI, `kubectl`, Helm ≥ 3.
- Credenciais AWS válidas (conta AWS Academy `voclabs` — a sessão expira
  em ~4h e precisa ser renovada periodicamente).
- Bucket S3 + tabela DynamoDB do state remoto, criados manualmente uma
  vez antes do primeiro `terraform init` (não fazem parte deste
  Terraform — o *state* não pode ser gerenciado pelo próprio recurso
  que ele descreve).

## Variáveis sensíveis

Nunca commitadas — vêm de GitHub Secrets na CI, ou de `-var` na mão
localmente: `auth_db_password`, `video_db_password`, `jwt_secret`,
`smtp_user`, `smtp_password`, `grafana_admin_password`.

## Testes / validação

Este repo não tem lógica de aplicação (é Terraform + Helm +
docker-compose), então "teste" aqui é validação estática — sem
precisar de credenciais AWS nem tocar em infra real:

```bash
cd terraform
terraform fmt -check -recursive   # formatação
terraform init -backend=false     # baixa os providers, sem configurar o state remoto
terraform validate                # sintaxe e referências entre recursos
```

Pra validar o `docker-compose` local (sem subir nada):

```bash
cd local
docker compose config --quiet     # valida o YAML e os builds referenciados
```

E pra validar de fato, ponta a ponta — sobe o sistema completo local e
segue os passos de ["Rodando localmente"](#rodando-localmente-sem-aws)
abaixo.

## Provisionando a AWS de verdade

```bash
cd terraform
terraform init -backend-config="bucket=fiapx-tf-state-<seu-account-id>"
terraform plan \
  -var="auth_db_password=..." -var="video_db_password=..." \
  -var="jwt_secret=..." -var="smtp_user=..." -var="smtp_password=..."
terraform apply ...
```

Cria VPC, EKS, 2× RDS, 5× ECR e o bucket S3 — ~15-20 min. Numa conta AWS
Academy `voclabs`, as credenciais são temporárias (expiram em ~4h);
renove a sessão se o `apply` demorar mais que isso.

## Depois do `apply` — deixando o cluster pronto pro primeiro deploy

```bash
aws eks update-kubeconfig --region us-east-1 --name fiapx-cluster
kubectl apply -f k8s/ingress/rules.yaml

# Dashboard do Grafana — gerado a partir do JSON real (fonte única,
# compartilhada com o Grafana local do docker-compose), com o label que
# o sidecar do Grafana procura:
kubectl create configmap fiapx-overview-dashboard -n monitoring \
  --from-file=fiapx-overview.json=k8s/observability/dashboards/fiapx-overview.json \
  --dry-run=client -o yaml \
  | kubectl label -f - --local -o yaml grafana_dashboard=1 \
  | kubectl apply -f -

# Secrets (JWT_SECRET, senhas de banco, credenciais SMTP) — rode uma vez,
# manualmente, com os valores reais (nunca commitados):
export DB_HOST=$(terraform -chdir=terraform output -raw db_endpoints | jq -r .auth) \
       DB_PASSWORD_AUTH=... DB_PASSWORD_VIDEO=... JWT_SECRET=... \
       SMTP_HOST=... SMTP_USER=... SMTP_PASSWORD=...
./scripts/create-service-secrets.sh
```

## Monitoramento

Prometheus + Grafana via `kube_prometheus_stack` (Helm, chart oficial
`prometheus-community`). Os 4 serviços Go expõem `/metrics` de verdade
(`http_requests_total`, `http_request_duration_seconds` — contagem e
latência por rota/método/status) e cada `deployment.yaml` já leva as
annotations `prometheus.io/scrape` — o Prometheus descobre e faz scrape
sozinho via `additionalScrapeConfigs`
(`k8s/observability/prometheus-values.yaml`), sem precisar de
`ServiceMonitor` por serviço.

[`k8s/observability/dashboards/fiapx-overview.json`](k8s/observability/dashboards/fiapx-overview.json)
é um dashboard real do Grafana (não os genéricos que vêm de fábrica com
o chart) — a mesma fonte usada localmente (ver `local/` mais abaixo),
gerada num ConfigMap com o label `grafana_dashboard=1` pelo comando
acima, que o sidecar do Grafana carrega sozinho, sem import manual pela
UI a cada `helm install` novo. Duas seções:

- **Vídeos** — contadores brutos (enviado/processado/falhou/frames/
  e-mails/cadastros), sobem em degrau a cada evento real — pensado pra
  aparecer claramente numa gravação curta, não só numa carga sustentada.
- **HTTP** — taxa de requisição, taxa de erro 5xx e latência p95 por
  serviço, breakdown por status.

### Gravando o dashboard localmente (sem precisar da AWS)

`local/docker-compose.yml` já sobe Prometheus + Grafana com o mesmo
dashboard, sem nenhum passo extra — testado de ponta a ponta:

```bash
cd local
docker compose up --build
```

Abra [http://localhost:3000](http://localhost:3000) (`admin` /
`fiapx-local`) → **Dashboards** → **FIAP X — Serviços** já está lá.
Deixa essa aba aberta e, numa outra, use o frontend
([http://localhost:8085](http://localhost:8085)) normalmente — cadastro,
login, upload de um vídeo válido e de um inválido (pra gerar sucesso e
falha). Os números do topo (vídeos enviados/processados/com
falha/frames/e-mails/cadastros) sobem ao vivo, o refresh do dashboard é
automático (5s) — não precisa apertar nada.

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
# login: admin / senha de grafana_admin_password (var do terraform apply)
# Dashboards → FIAP X — Serviços
```

Com isso feito, cada serviço faz o próprio deploy disparando manualmente
o job `deploy` do seu `ci.yml` no GitHub Actions (build → push pro ECR →
`kubectl apply` → migration, quando tem banco → rollout). Ver a seção
"Deploy" do README de cada repo pros Secrets/Variables que ele espera —
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` (as
mesmas credenciais temporárias, uma vez por repo) e
`S3_BUCKET_NAME` como Variable (não Secret — não é sensível), com o
valor de `terraform output videos_bucket_name`, nos repos que falam com
S3 (`video-service`, `processing-worker`). Nenhum desses jobs roda
sozinho em push/PR — só via disparo manual (workflow_dispatch),
justamente porque pressupõem que os passos acima já rodaram.

## Rodando localmente (sem AWS)

[`local/docker-compose.yml`](local/docker-compose.yml) sobe o sistema
completo sem depender de AWS: MinIO no lugar do S3, Mailpit no lugar do
SMTP real, Kafka self-hosted (KRaft, single node), Postgres×2 e Redis —
mesmo desenho do que roda em produção, só trocando os serviços gerenciados
por equivalentes locais. Pressupõe os 6 repos de serviço clonados como
irmãos deste (`fiapx-infra`), não dentro dele:

```
tech-garage/
├── fiapx-infra/local/docker-compose.yml   (aqui)
├── fiapx-auth-service/
├── fiapx-video-service/
├── fiapx-processing-worker/
├── fiapx-notification-service/
├── fiapx-events/
└── fiapx-frontend/
```

```bash
cd local
docker compose up --build
```

| Serviço | URL |
|---|---|
| Frontend | http://localhost:8085 |
| Auth API | http://localhost:8081 |
| Video API | http://localhost:8082 |
| Worker `/health` | http://localhost:8083/health |
| Notification `/health` | http://localhost:8084/health |
| MinIO console | http://localhost:9001 (minioadmin/minioadmin) |
| Mailpit UI | http://localhost:8025 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 (admin/fiapx-local) — dashboard "FIAP X — Serviços" já carregado |

## Testando a API

[`docs/postman/fiapx-collection.json`](docs/postman/fiapx-collection.json)
— coleção Postman completa dos 4 serviços (Auth, Video, Worker,
Notification): register/login/me, upload/list/get/download de vídeo, e
os endpoints de operação (`/health`, `/ready`, `/metrics`) de cada um.
Login salva o JWT automaticamente em `{{token}}`; upload salva o
`{{video_id}}` — as demais requests já usam essas variáveis. As URLs
base já apontam pras portas do `local/docker-compose.yml` acima
(`8081`-`8084`); troque as variáveis da coleção se for testar contra um
cluster real.

## Destruir

```bash
cd terraform
terraform destroy -var="auth_db_password=..." -var="video_db_password=..." \
  -var="jwt_secret=..." -var="smtp_user=..." -var="smtp_password=..."
```

Nada aqui tem `deletion_protection` — destroy roda sem passo manual extra.
