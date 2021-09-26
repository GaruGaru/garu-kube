#!/bin/bash

set -exu

BRANCH=${BRANCH:?'missing BRANCH env var'}
KIND_IMAGE="kindest/node:v1.20.2"
KIND_CLUSTER_NAME="kind-garu-kube-e2e"
KIND_KUBECONF_PATH="kind-kubeconf.yml"

FLUX_TARGET_PATH=./core/overlays/base

logStatus () {
  kubectl --kubeconfig="${KIND_KUBECONF_PATH}" get kustomization -A || true
  kubectl --kubeconfig="${KIND_KUBECONF_PATH}" get pods -A || true
  kubectl --kubeconfig="${KIND_KUBECONF_PATH}" get deployments -A || true
  kubectl --kubeconfig="${KIND_KUBECONF_PATH}" -n flux-system get all || true
  kubectl --kubeconfig="${KIND_KUBECONF_PATH}" -n flux-system logs deploy/source-controller || true
  kubectl --kubeconfig="${KIND_KUBECONF_PATH}" -n flux-system logs deploy/kustomize-controller || true
  kubectl --kubeconfig="${KIND_KUBECONF_PATH}" -n flux-system logs deploy/helm-controller || true
  kubectl --kubeconfig="${KIND_KUBECONF_PATH}" get pod --all-namespaces | grep -v Running | grep -v Completed | grep -v NAMESPACE | awk '{print " kubectl -n " $1 " describe pod " $2}' | sh || true
}

cleanup() {
  rm ${KIND_KUBECONF_PATH} &> /dev/null || true
  kind delete cluster --name ${KIND_CLUSTER_NAME} &> /dev/null || true
}

logStatusAndClean() {
  logStatus;
  cleanup;
  echo "E2E end with exit code $?"
}

#cleanup old resources
cleanup

trap logStatusAndClean EXIT

# Create kubernetes cluster
kind create cluster --name ${KIND_CLUSTER_NAME} --image ${KIND_IMAGE} --kubeconfig=${KIND_KUBECONF_PATH}

# Install and bootstrap flux
flux --kubeconfig=${KIND_KUBECONF_PATH} check --pre && flux --kubeconfig=${KIND_KUBECONF_PATH} install
yes | flux --kubeconfig=${KIND_KUBECONF_PATH} create source git flux-system --private-key-file=ssh/id_rsa --url=ssh://git@github.com/garugaru/garu-kube.git --branch="${BRANCH}"
flux --kubeconfig=${KIND_KUBECONF_PATH} create kustomization flux-system --source=flux-system --path=${FLUX_TARGET_PATH}

# Wait and verify flux kustomization
kubectl --kubeconfig=${KIND_KUBECONF_PATH} -n flux-system wait kustomization/flux-system --for=condition=ready --timeout=300s

# Wait and verify helmreleases
flux_helm_releases_ns=($(kubectl --kubeconfig="${KIND_KUBECONF_PATH}" get helmreleases --all-namespaces | awk '{print $1}' | grep -v NAME))
flux_helm_releases=($(kubectl --kubeconfig="${KIND_KUBECONF_PATH}" get helmreleases --all-namespaces | awk '{print $2}' | grep -v NAME))

for i in "${!flux_helm_releases_ns[@]}"
do
    echo "checking helmrelease: ${flux_helm_releases_ns[$i]}/${flux_helm_releases[$i]}"
    kubectl --kubeconfig="${KIND_KUBECONF_PATH}" wait helmreleases/"${flux_helm_releases[$i]}" --for=condition=ready -n "${flux_helm_releases_ns[$i]}" --timeout=300s
done

echo "E2E tests completed"
exit 0
