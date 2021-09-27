#!/usr/bin/env bash

set -o errexit
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

usage(){
	echo "Usage: $0 APP_NAME ENV"
    echo "Example: $0 spring-petclinic dev"
	exit 1
}

[[ $# -eq 0 ]] && usage

APP_NAME=${1:-spring-petclinic}
ENV=${2:-dev}

LATEST_IMAGE=$(kubectl get image spring-petclinic-image -n spring-petclinic -o jsonpath="{.status.latestImage}")
CURRENT_IMAGE=$(yq e .spec.template.spec.containers[0].image "$SCRIPT_DIR/../argocd/$APP_NAME/$ENV/deployment.yaml")
sed -i "s|$CURRENT_IMAGE|$LATEST_IMAGE|" "$SCRIPT_DIR/../argocd/$APP_NAME/$ENV/deployment.yaml"

git diff "$SCRIPT_DIR/../argocd/$APP_NAME/$ENV/deployment.yaml"