#!/usr/bin/env bash

# This script will create 3 folders in the examples directory:
# - initial: contains the state before pushing apps
# - after-push-a: contains the state after pushing one app
# - after-push-b: contains the state after pushing another app
#
# The state are the envoy config of the app-sidecars and the istio-ingressgateway and all CF and Istio objects.
#
# Tip: Then comparing envoy dumps it helps to sort the json before comparing, e.g.:
# diff -u <(jq -S . after-push-a/ingress.json) <(jq -S . after-push-b/ingress.json)

set -euo pipefail

NODE_APP_DIR="${NODE_APP_DIR:-$HOME/workspace/cf-for-k8s/tests/smoke/assets/test-node-app}"
API_PREFIX="https://api."
RAW_DOMAIN="$(kubectl config view -o json | jq -r '.clusters[0].cluster.server')"
DOMAIN_PREFIX="${DOMAIN_PREFIX:-cf}"
DOMAIN="${DOMAIN_PREFIX}.${RAW_DOMAIN#"$API_PREFIX"}"

echo "Using Domain: $DOMAIN"
ADMIN_PWD="$(kubectl get secret var-cf-admin-password -n kubecf -o json | jq -r '.data.password' | base64 -d)"
echo "Admin password: $ADMIN_PWD"
cf api https://api.$DOMAIN
cf auth admin "$ADMIN_PWD" --origin uaa

CF_RESOURCES=$(kubectl api-resources -o name | grep cloudfoundry | tr '\n' , | sed 's/,$//')
ISTIO_RESOURCES=$(kubectl api-resources -o name | grep istio | tr '\n' , | sed 's/,$//')

function push_app() {
    cf create-org test-$1
    cf create-space test -o test-$1
    cf target -o test-$1 -s test
    cf push test-app-$1 -p "${NODE_APP_DIR}"
    cf apps
    URL="$(cf app test-app-$1  | awk '/routes:/ { print $2 }')"
    curl -f "https://$URL"
}

function dump_envoy() {
    local NAMESPACE=$1
    local NAME=$2
    local TARGET=$3
    local PID
    kubectl port-forward -n "$NAMESPACE" "$NAME" 15000:15000 &
    PID=$!
    sleep 1
    curl -so "$TARGET" http://localhost:15000/config_dump
    kill $PID
}

# Inital dump
INGRESS_POD_NAME=$(kubectl get pod -n istio-system -l app=istio-ingressgateway -o name | head -n 1)

mkdir -p examples/initial
dump_envoy istio-system "$INGRESS_POD_NAME" ./examples/initial/ingress.json
kubectl get "$ISTIO_RESOURCES" -A -o yaml > ./examples/initial/istio.yaml
kubectl get "$CF_RESOURCES" -A -o yaml > ./examples/initial/cf.yaml

# Push app a
push_app a

# Dump config
GUID_A="$(cf app --guid test-app-a)"
POD_NAME_A=$(kubectl get pods -n cf-workloads -l "cloudfoundry.org/app_guid=$GUID_A" -o name)

mkdir -p examples/after-push-a
dump_envoy cf-workloads "$POD_NAME_A" ./examples/after-push-a/pod_a.json
dump_envoy istio-system "$INGRESS_POD_NAME" ./examples/after-push-a/ingress.json
kubectl get "$ISTIO_RESOURCES" -A -o yaml > ./examples/after-push-a/istio.yaml
kubectl get "$CF_RESOURCES" -A -o yaml > ./examples/after-push-a/cf.yaml

# Push app b
push_app b

# Dump config
GUID_B="$(cf app --guid test-app-b)"
POD_NAME_B=$(kubectl get pods -n cf-workloads -l "cloudfoundry.org/app_guid=$GUID_B" -o name)

mkdir -p examples/after-push-b
dump_envoy cf-workloads "$POD_NAME_A" ./examples/after-push-b/pod_a.json
dump_envoy cf-workloads "$POD_NAME_B" ./examples/after-push-b/pod_b.json
dump_envoy istio-system "$INGRESS_POD_NAME" ./examples/after-push-b/ingress.json
kubectl get "$ISTIO_RESOURCES" -A -o yaml > ./examples/after-push-b/istio.yaml
kubectl get "$CF_RESOURCES" -A -o yaml > ./examples/after-push-b/cf.yaml

# Add another route to app b
cf map-route test-app-b "${DOMAIN}" --hostname test-app-b1

mkdir -p examples/after-map-route-b
dump_envoy cf-workloads "$POD_NAME_A" ./examples/after-map-route-b/pod_a.json
dump_envoy cf-workloads "$POD_NAME_B" ./examples/after-map-route-b/pod_b.json
dump_envoy istio-system "$INGRESS_POD_NAME" ./examples/after-map-route-b/ingress.json
kubectl get "$ISTIO_RESOURCES" -A -o yaml > ./examples/after-map-route-b/istio.yaml
kubectl get "$CF_RESOURCES" -A -o yaml > ./examples/after-map-route-b/cf.yaml

cf delete-org -f test-a
cf delete-org -f test-b
