# ============================================================
# Helm releases: Ingress NGINX, Kafka (self-hosted), Redis,
# Prometheus + Grafana.
#
# Kafka e Redis via chart Bitnami — mesmo catálogo já usado com sucesso
# pra RabbitMQ em autorepair-infra-k8s na Fase 4 (helm.tf de lá não
# existe porque aquele deploy roda direto na CI, não via Terraform; aqui
# preferimos Terraform pra ter o estado de toda a infra em um só lugar).
# ============================================================

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.x"
  namespace        = "ingress-nginx"
  create_namespace = true

  timeout = 600

  depends_on = [aws_eks_node_group.default]
}

resource "helm_release" "kafka" {
  name             = "kafka"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "kafka"
  version          = "31.x"
  namespace        = "fiapx"
  create_namespace = false

  # KRaft mode (sem Zookeeper), 1 broker — node group pequeno demais
  # (AWS Academy) pra justificar um cluster Kafka multi-broker num
  # hackathon de alguns dias. Sem auth/TLS: Kafka só é alcançável
  # dentro do cluster (ClusterIP), nunca exposto via Ingress.
  set {
    name  = "kraft.enabled"
    value = "true"
  }
  set {
    name  = "controller.replicaCount"
    value = "1"
  }
  set {
    name  = "listeners.client.protocol"
    value = "PLAINTEXT"
  }
  set {
    name  = "persistence.size"
    value = "8Gi"
  }

  timeout    = 600
  wait       = false # ver justificativa em autorepair-infra-k8s/terraform/main.tf (Datadog) — pods grandes demoram mais que o default de 5min pra ficar Ready num node pequeno
  depends_on = [kubernetes_namespace.fiapx, aws_eks_node_group.default]
}

resource "helm_release" "redis" {
  name             = "redis"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "redis"
  version          = "20.x"
  namespace        = "fiapx"
  create_namespace = false

  # standalone (sem replica): cache de status + idempotência não
  # justificam HA de Redis nesse escopo. auth desabilitado — só
  # alcançável dentro do cluster.
  set {
    name  = "architecture"
    value = "standalone"
  }
  set {
    name  = "auth.enabled"
    value = "false"
  }
  set {
    name  = "master.persistence.size"
    value = "2Gi"
  }

  timeout    = 600
  wait       = false
  depends_on = [kubernetes_namespace.fiapx, aws_eks_node_group.default]
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "65.x"
  namespace        = "monitoring"
  create_namespace = true

  # kube-prometheus-stack (Prometheus Operator) discovers targets via
  # ServiceMonitor/PodMonitor CRDs by default — it does NOT read the
  # classic prometheus.io/scrape pod annotations already present on each
  # fiapx-* Deployment. ../k8s/observability/prometheus-values.yaml adds
  # an additionalScrapeConfigs block that makes it honor those
  # annotations instead of requiring a ServiceMonitor per service.
  values = [file("${path.module}/../k8s/observability/prometheus-values.yaml")]

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  timeout    = 900
  wait       = false
  depends_on = [aws_eks_node_group.default]
}
