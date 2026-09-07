#!/usr/bin/env bash
# Cria (ou atualiza) os 3 Secrets do cluster fiapx à mão, direto do seu
# kubectl local — útil pra um primeiro setup manual ou pra recriar um
# secret sem precisar disparar o workflow de deploy de um serviço.
#
# Cada serviço também cria/atualiza o PRÓPRIO Secret sozinho, dentro do
# seu job "deploy" (ver .github/workflows/ci.yml de cada repo) — este
# script é só um atalho manual que documenta, num lugar só, TODOS os
# valores que o cluster inteiro precisa. As duas formas são idempotentes
# e convergem pro mesmo resultado (kubectl apply, não create puro).
#
# Uso: exporte as variáveis abaixo e rode.
#   export DB_HOST=... DB_PASSWORD_AUTH=... DB_PASSWORD_VIDEO=... \
#          JWT_SECRET=... SMTP_HOST=... SMTP_USER=... SMTP_PASSWORD=...
#   ./scripts/create-service-secrets.sh
#
# Pressupõe: kubectl já apontando pro cluster certo
# (aws eks update-kubeconfig --name fiapx-cluster --region us-east-1).

set -euo pipefail

required_vars=(DB_HOST DB_PASSWORD_AUTH DB_PASSWORD_VIDEO JWT_SECRET SMTP_HOST SMTP_USER SMTP_PASSWORD)
for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "erro: variável $v não definida (ver o cabeçalho deste script)" >&2
    exit 1
  fi
done

kubectl create namespace fiapx --dry-run=client -o yaml | kubectl apply -f -

echo "-- fiapx-auth-secret"
kubectl create secret generic fiapx-auth-secret -n fiapx \
  --from-literal=DB_URL="postgres://auth:${DB_PASSWORD_AUTH}@${DB_HOST}:5432/fiapx_auth?sslmode=require" \
  --from-literal=JWT_SECRET="${JWT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "-- fiapx-video-secret"
kubectl create secret generic fiapx-video-secret -n fiapx \
  --from-literal=DB_URL="postgres://video:${DB_PASSWORD_VIDEO}@${DB_HOST}:5432/fiapx_video?sslmode=require" \
  --from-literal=JWT_SECRET="${JWT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "-- fiapx-notification-secret"
kubectl create secret generic fiapx-notification-secret -n fiapx \
  --from-literal=SMTP_HOST="${SMTP_HOST}" \
  --from-literal=SMTP_USER="${SMTP_USER}" \
  --from-literal=SMTP_PASSWORD="${SMTP_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "ok — 3 secrets aplicados no namespace fiapx"
