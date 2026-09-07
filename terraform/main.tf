# ============================================================
# FIAP X — Infraestrutura (Hackathon SOAT, Fase 5)
# Provisiona: VPC, EKS Cluster, ECR (4 serviços + frontend), S3 (vídeos),
# namespace k8s. Kafka/Redis/Prometheus/Ingress vêm via Helm — ver
# helm.tf. RDS (Auth + Video) vêm via rds.tf.
# ============================================================

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # AWS Academy voclabs accounts don't allow creating IAM roles — LabRole
  # is the pre-existing role every service (EKS, RDS, node group) must
  # reuse. Same constraint already documented in autorepair-infra-k8s.
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"

  ecr_repos = {
    auth         = "fiapx-auth-service"
    video        = "fiapx-video-service"
    worker       = "fiapx-processing-worker"
    notification = "fiapx-notification-service"
    frontend     = "fiapx-frontend"
  }
}

# ---------------------------------------------------------------
# VPC
# ---------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# ---------------------------------------------------------------
# EKS Cluster
# ---------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = local.lab_role_arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids             = module.vpc.private_subnets
    endpoint_public_access = true
  }

  depends_on = [module.vpc]
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = local.lab_role_arn
  subnet_ids      = module.vpc.private_subnets

  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  depends_on = [aws_eks_cluster.this]
}

# ---------------------------------------------------------------
# ECR — um repositório por serviço
# ---------------------------------------------------------------
resource "aws_ecr_repository" "services" {
  for_each = local.ecr_repos

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------
# S3 — armazenamento dos vídeos (raw + processado)
# ---------------------------------------------------------------
resource "aws_s3_bucket" "videos" {
  # Bucket S3 é único GLOBALMENTE — sufixo do account id evita colisão
  # com outra conta/sessão AWS Academy que já tenha usado esse nome.
  bucket        = "fiapx-videos-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_cors_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id

  # O frontend baixa o zip de frames via fetch() (pra descompactar no
  # navegador e mostrar a galeria, não só "salvar arquivo") — sem CORS
  # aqui, o navegador bloqueia a leitura da resposta mesmo com a URL
  # pré-assinada sendo válida. GET only: a única forma de acessar
  # qualquer objeto deste bucket é via URL pré-assinada (bucket é
  # privado, ver aws_s3_bucket_public_access_block abaixo) — a própria
  # assinatura já é o controle de acesso, então liberar a origem pra
  # "*" não amplia o que já é acessível, só permite o navegador LER a
  # resposta de uma URL que ele já teria permissão de baixar de outra
  # forma (download direto).
  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_versioning" "videos" {
  bucket = aws_s3_bucket.videos.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "videos" {
  bucket = aws_s3_bucket.videos.id

  # Vídeo bruto só é lido uma vez (pelo worker); frames processados só
  # importam enquanto o usuário não baixou o zip. 7 dias é generoso pra
  # demo/avaliação sem deixar arquivo de vídeo acumulando indefinidamente.
  rule {
    id     = "expire-raw-and-processed"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    expiration {
      days = 7
    }
  }

  rule {
    id     = "expire-processed"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "videos" {
  bucket = aws_s3_bucket.videos.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------
# Namespace fiapx — compartilhado pelos 4 serviços
# ---------------------------------------------------------------
resource "kubernetes_namespace" "fiapx" {
  metadata {
    name = "fiapx"
    labels = {
      app         = "fiapx"
      environment = var.environment
    }
  }

  depends_on = [aws_eks_node_group.default]
}
