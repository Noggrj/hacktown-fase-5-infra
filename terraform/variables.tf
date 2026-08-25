variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Região AWS para provisionamento"
}

variable "cluster_name" {
  type        = string
  default     = "fiapx-cluster"
  description = "Nome do cluster EKS"
}

variable "cluster_version" {
  type        = string
  default     = "1.32"
  description = "Versão do Kubernetes no EKS"
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Ambiente: staging | production"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment deve ser 'staging' ou 'production'."
  }
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block da VPC"
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Tipos de instância dos nodes EKS — precisa caber Kafka+Redis+Prometheus+4 serviços num node group pequeno de conta AWS Academy"
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 6
}

# ---------------------------------------------------------------
# Bancos de dados (Auth Service, Video Service)
# ---------------------------------------------------------------
variable "auth_db_password" {
  type        = string
  sensitive   = true
  description = "Senha do RDS do Auth Service"
}

variable "video_db_password" {
  type        = string
  sensitive   = true
  description = "Senha do RDS do Video Service"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = "Classe de instância dos 2 RDS — hackathon de curta duração, sem tráfego real"
}

variable "db_multi_az" {
  type        = bool
  default     = false
  description = "Multi-AZ desabilitado por padrão — dobra o custo do RDS sem necessidade para uma demo de vídeo de alguns dias"
}

# deletion_protection=true em produção real seria o padrão certo, mas
# essa infra tem vida curta (subir, gravar o vídeo, destruir) — manter
# ligado só adiciona um passo manual de "desprotege antes de destruir"
# a cada ciclo, sem proteger nada que valha a pena proteger aqui.
variable "db_deletion_protection" {
  type        = bool
  default     = false
  description = "Proteção contra deleção acidental do RDS"
}

# ---------------------------------------------------------------
# JWT compartilhado entre Auth Service e Video Service
# ---------------------------------------------------------------
variable "jwt_secret" {
  type        = string
  sensitive   = true
  description = "Segredo HS256 compartilhado — mesmo valor em fiapx-auth-secret e fiapx-video-secret"
}

# ---------------------------------------------------------------
# SMTP (Notification Service)
# ---------------------------------------------------------------
variable "smtp_host" {
  type        = string
  default     = "sandbox.smtp.mailtrap.io"
  description = "Host SMTP — Mailtrap sandbox por padrão"
}

variable "smtp_user" {
  type        = string
  sensitive   = true
  description = "Usuário SMTP"
}

variable "smtp_password" {
  type        = string
  sensitive   = true
  description = "Senha/token SMTP"
}

# ---------------------------------------------------------------
# Observabilidade
# ---------------------------------------------------------------
variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  default     = "fiapx-admin"
  description = "Senha do usuário admin do Grafana — trocar antes de expor a UI publicamente"
}
