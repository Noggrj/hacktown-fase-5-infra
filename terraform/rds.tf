# ============================================================
# RDS PostgreSQL — um por serviço com estado (Auth, Video).
# Processing Worker e Notification Service não têm banco próprio
# (idempotência via Redis) — ver README de cada um.
# ============================================================

resource "aws_security_group" "rds" {
  name_prefix = "fiapx-rds-${var.environment}-"
  vpc_id      = module.vpc.vpc_id
  description = "FIAP X RDS — acesso restrito aos workloads do EKS"

  ingress {
    description = "PostgreSQL from EKS node group"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_subnet_group" "fiapx" {
  name       = "fiapx-${var.environment}"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "fiapx-${var.environment}-subnet-group"
  }
}

locals {
  databases = {
    auth = {
      identifier = "fiapx-auth-${var.environment}"
      db_name    = "fiapx_auth"
      username   = "auth_admin"
      password   = var.auth_db_password
    }
    video = {
      identifier = "fiapx-video-${var.environment}"
      db_name    = "fiapx_video"
      username   = "video_admin"
      password   = var.video_db_password
    }
  }
}

resource "aws_db_instance" "services" {
  for_each = local.databases

  identifier = each.value.identifier
  engine     = "postgres"
  # Só a versão major: a AWS descontinua patches específicos e resolve
  # pro minor padrão vigente automaticamente sem quebrar o apply.
  engine_version    = "16"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_encrypted = true
  storage_type      = "gp3"

  db_name  = each.value.db_name
  username = each.value.username
  password = each.value.password

  db_subnet_group_name   = aws_db_subnet_group.fiapx.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = var.db_multi_az
  publicly_accessible = false
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = true

  backup_retention_period = 1

  tags = {
    Name    = each.value.identifier
    Service = each.key
  }
}
