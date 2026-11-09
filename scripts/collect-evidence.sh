#!/usr/bin/env bash
# Save non-sensitive Kubernetes and smoke-test outputs for Devsu assessment.
# Run from repository root: bash scripts/collect-evidence.sh
set -euo pipefail
mkdir -p evidence
{
  printf 'Collected (UTC): '; date -u '+%Y-%m-%dT%H:%M:%SZ'
  printf '\nKubernetes context:\n'; kubectl config current-context
  printf '\nNodes:\n'; kubectl get nodes
  printf '\nAPI and database resources:\n'; kubectl -n devsu get deployments,pods,services,ingress,hpa,pvc
  printf '\nHPA metrics:\n'; kubectl -n devsu get hpa
  printf '\nPods resource usage:\n'; kubectl -n devsu top pods
  printf '\nRecent migration result:\n'; kubectl -n devsu get job db-migrate
} > evidence/kubernetes-status.txt

# Reach Service without exposing it on the internet.
kubectl -n devsu port-forward svc/devsu-api 18080:80 > /tmp/devsu-evidence-service-pf.log 2>&1 &
PF_SERVICE=$!
PF_TRAEFIK=''
cleanup() {
  kill "$PF_SERVICE" 2>/dev/null || true
  if [ -n "$PF_TRAEFIK" ]; then kill "$PF_TRAEFIK" 2>/dev/null || true; fi
}
trap cleanup EXIT

attempt_curl() {
  local dest="$1"; shift
  local success=1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl --noproxy '*' --max-time 3 --fail-with-body -si "$@" > "$dest" 2>/dev/null; then
      success=0; break
    fi
    sleep 1
  done
  return "$success"
}

if attempt_curl evidence/service-http.txt http://127.0.0.1:18080/api/users/; then
  echo 'Service smoke test saved: evidence/service-http.txt'
else
  echo 'Service smoke test failed; see /tmp/devsu-evidence-service-pf.log' >&2
  exit 1
fi

if kubectl -n kube-system get svc traefik >/dev/null 2>&1; then
  kubectl -n kube-system port-forward svc/traefik 18081:80 > /tmp/devsu-evidence-traefik-pf.log 2>&1 &
  PF_TRAEFIK=$!
  if attempt_curl evidence/ingress-http.txt -H 'Host: devsu.local' http://127.0.0.1:18081/api/users/; then
    echo 'Ingress smoke test saved: evidence/ingress-http.txt'
  else
    echo 'Ingress smoke test failed; inspect Traefik and app pods' >&2
    exit 1
  fi
else
  echo 'Traefik Service not found; skipping Ingress smoke test.' >&2
fi

echo 'Saved Kubernetes evidence in ./evidence/ (no secrets exported).'
