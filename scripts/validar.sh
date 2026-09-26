#!/usr/bin/env bash
# Valida a entrega do CP1 em um cluster já configurado no kubectl (kind ou Minikube):
# aplica os manifestos, espera os Pods, acessa a página pelo Service e escala o Deployment.
set -euo pipefail

NS=safebank-will
PORTA_LOCAL="${PORTA_LOCAL:-18080}"
REPLICAS="${REPLICAS:-15}"
cd "$(dirname "$0")/.."

echo "1) Aplicando os manifestos"
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/

echo "2) Esperando o Deployment e o Pod avulso"
kubectl -n "$NS" rollout status deploy/safebank-app --timeout=180s
kubectl -n "$NS" wait --for=condition=Ready pod/safebank-app --timeout=120s
kubectl -n "$NS" get pods,svc -o wide

echo "3) Acessando a página pelo Service (port-forward em localhost:$PORTA_LOCAL)"
kubectl -n "$NS" port-forward svc/safebank-app "$PORTA_LOCAL":80 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do
  curl -fs "http://localhost:$PORTA_LOCAL/healthz" >/dev/null 2>&1 && break
  sleep 1
done
curl -fs "http://localhost:$PORTA_LOCAL/healthz"
PAGINA=$(curl -fs "http://localhost:$PORTA_LOCAL/")
grep -q "SafeBank Digital" <<<"$PAGINA"
POD=$(grep -o 'Pod <strong>[^<]*' <<<"$PAGINA" | sed 's/.*<strong>//')
echo "   Página OK, servida pelo Pod: $POD"

echo "4) Escalando o Deployment para $REPLICAS réplicas"
kubectl -n "$NS" scale deployment safebank-app --replicas="$REPLICAS"
kubectl -n "$NS" rollout status deploy/safebank-app --timeout=300s
PRONTAS=$(kubectl -n "$NS" get deploy safebank-app -o jsonpath='{.status.readyReplicas}')
echo "   Réplicas prontas: $PRONTAS de $REPLICAS"
[ "$PRONTAS" = "$REPLICAS" ]

echo "5) Voltando para 2 réplicas"
kubectl -n "$NS" scale deployment safebank-app --replicas=2
kubectl -n "$NS" rollout status deploy/safebank-app --timeout=120s

echo "Validação concluída."
