terraform {
  # `bucket` fica de fora de propósito — nomes de bucket S3 são únicos
  # GLOBALMENTE (entre todas as contas AWS). A CI passa
  # "-backend-config=bucket=fiapx-tf-state-<account-id>" no `terraform
  # init` (ver .github/workflows/ci.yml), com o account id da própria
  # sessão AWS Academy, garantindo unicidade sem hardcode — mesmo padrão
  # já validado em autorepair-infra-k8s na Fase 4.
  backend "s3" {
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "fiapx-tf-locks"
  }
}
