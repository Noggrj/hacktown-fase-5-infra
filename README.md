# fiapx-infra

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
| Terraform | VPC, cluster EKS + node group, 2× RDS PostgreSQL (Auth, Video), 4× ECR, bucket S3 (vídeos), namespace `fiapx` |
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
- Bucket S3 + tabela DynamoDB do state remoto (criados automaticamente,
  de forma idempotente, pela CI — ver `.github/workflows/ci.yml`).

## Variáveis sensíveis

Nunca commitadas — vêm de GitHub Secrets na CI, ou de `-var` na mão
localmente: `auth_db_password`, `video_db_password`, `jwt_secret`,
`smtp_user`, `smtp_password`, `grafana_admin_password`.

## Uso local

```bash
cd terraform
terraform init -backend-config="bucket=fiapx-tf-state-<seu-account-id>"
terraform plan \
  -var="auth_db_password=..." -var="video_db_password=..." \
  -var="jwt_secret=..." -var="smtp_user=..." -var="smtp_password=..."
terraform apply ...
```

## Depois do `apply`

```bash
aws eks update-kubeconfig --region us-east-1 --name fiapx-cluster
kubectl apply -f ../fiapx-infra/k8s/ingress/rules.yaml
# aplicar os Secrets reais de cada serviço (ver scripts/create-service-secrets.sh)
# aplicar os Jobs de migration do Postgres (ver k8s/migrations/)
```

## Destruir

```bash
cd terraform
terraform destroy -var="auth_db_password=..." -var="video_db_password=..." \
  -var="jwt_secret=..." -var="smtp_user=..." -var="smtp_password=..."
```

Nada aqui tem `deletion_protection` — destroy roda sem passo manual extra.
