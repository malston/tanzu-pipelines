#!/usr/bin/env bash

function die() {
    2>&1 echo "$@"
    exit 1
}

function login_harbor() {
    echo "${REGISTRY_PASSWORD}" | docker login -u admin "${REGISTRY}" --password-stdin
}

function create_harbor_projects() {
   for p in {concourse-images,kpack,tanzu}; do
     echo "Creating '${p}' in Harbor."
     curl --user "admin:${REGISTRY_PASSWORD}" -X POST \
         "https://${REGISTRY}/api/v2.0/projects" \
         -H "Content-type: application/json" --data \
         '{ "project_name": "'${p}'",
          "metadata": {
          "auto_scan": "true",
          "enable_content_trust": "false",
          "prevent_vul": "false",
          "public": "true",
          "reuse_sys_cve_whitelist": "true",
          "severity": "high" }
          }'
    done
}

function build_kpack_concourse_resource() {
    # Container: pipeline talks to kpack
    docker pull gcr.io/cf-build-service-public/concourse-kpack-resource:1.0
    docker tag gcr.io/cf-build-service-public/concourse-kpack-resource:1.0 "$REGISTRY/concourse-images/concourse-kpack-resource:1.0"
    docker push "$REGISTRY/concourse-images/concourse-kpack-resource:1.0"
}

function build_kubectl_image() {
    local k8s_version="${1}"

    # Container: pipeline talks to k8s
    docker build --platform linux/amd64 --build-arg "KUBERNETES_VERSION=$k8s_version" --rm -t "$REGISTRY/concourse-images/kubectl-docker:$k8s_version" .
    docker push "$REGISTRY/concourse-images/kubectl-docker:$k8s_version"
}

DOMAIN="${DOMAIN:-"example.com"}"
REGISTRY="${REGISTRY:-"https://registry.${DOMAIN}"}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.20.7}"

if [[ -z "$REGISTRY_PASSWORD" ]]; then
    echo -n "Enter password for $REGISTRY: "
    read -rs REGISTRY_PASSWORD
    echo
fi

login_harbor || die "Check the password for $REGISTRY"
create_harbor_projects
build_kpack_concourse_resource
build_kubectl_image "$KUBERNETES_VERSION"
