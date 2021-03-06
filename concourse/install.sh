#!/usr/bin/env bash
#
# freshctl
# Fresh cloud command line client.

# source ../.envrc.sh

function die() {
    2>&1 echo "$@"
    exit 1
}

function create_secret_kpack() {
  kubectl delete secret docker-registry &> /dev/null
  echo "Creating docker-registry secret for ${APP_NAME}-registry-credentials"
  kubectl create secret docker-registry "${APP_NAME}-registry-credentials" \
      --docker-username=admin \
      --docker-password="${REGISTRY_PASSWORD}" \
      --docker-server="https://${REGISTRY}" \
      --namespace "${APP_NAME}"
}

function create_service_account_kpack() {

  echo "Creating a service account for kpack-${DEPLOY_KEY}-registry-credentials"
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_NAME}-service-account
  namespace: ${APP_NAME}
secrets:
- name: ${APP_NAME}-registry-credentials
$(
# shellcheck disable=SC2030
if [ -n "${DEPLOY_KEY}" ]; then
   echo "- name: ${APP_NAME}-deploy-key"
fi
)
imagePullSecrets:
- name: ${APP_NAME}-registry-credentials
EOF
}

function create_builder_kpack() {

  echo "Creating the kpack builder"
  cat <<EOF | kubectl apply -f -
apiVersion: kpack.io/v1alpha1
kind: Builder
metadata:
  name: ${APP_NAME}-builder
  namespace: ${APP_NAME}
spec:
  serviceAccount: ${APP_NAME}-service-account
  tag: harbor.markalston.net/kpack/builder
  stack:
    name: base
    kind: ClusterStack
  store:
    name: default
    kind: ClusterStore
  order:
  - group:
    - id: heroku/java
  - group:
    - id: heroku/nodejs
EOF
}

function create_app_image_spec() {

  echo "Creating the app image spec"
  cat <<EOF | kubectl apply -f -
apiVersion: kpack.io/v1alpha1
kind: Image
metadata:
  name: ${APP_NAME}-image
  namespace: ${APP_NAME}
spec:
  tag: harbor.markalston.net/tanzu/${APP_NAME}
  serviceAccount: ${APP_NAME}-service-account
  builder:
    kind: ClusterBuilder
    name: default
  source:
    git:
      url: ${APP_REPO}
      revision: ${APP_BRANCH}
EOF
}

function install_role_binding() {

  echo "Creating role and role binding"
  cat <<EOF | kubectl apply -f -
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  namespace: ${APP_NAME}
  name: ${APP_NAME}-image-role
rules:
- apiGroups: ["kpack.io", "", "networking.k8s.io", "apps"]
  resources: ["images", "builds", "pods", "pods/log", "services", "ingresses", "deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: ${APP_NAME}-image-role-binding
  namespace: ${APP_NAME}
subjects:
- kind: ServiceAccount
  name: ${APP_NAME}-service-account
  apiGroup: ""
roleRef:
  kind: Role
  name: ${APP_NAME}-image-role
  apiGroup: ""
EOF
}

function write_pipeline_params() {

  mkdir -p build
  echo "Writing pipeline params yaml"

  # Vars we need to add to our kubeconfig
  SERVER=$(kubectl cluster-info|head -1|awk '{print $NF}')
  NAME=$(kubectl get secrets -n "${APP_NAME}" |grep "${APP_NAME}-service-account-token" | awk '{print $1}')
  CA=$(kubectl get "secret/${NAME}" -n "${APP_NAME}" -o jsonpath='{.data.ca\.crt}')
  TOKEN=$(kubectl get "secret/${NAME}" -n "${APP_NAME}" -o jsonpath='{.data.token}' | base64 --decode)
  # NAMESPACE=$(kubectl get "secret/${NAME}" -n "${APP_NAME}" -o jsonpath='{.data.namespace}' | base64 --decode)

  # Create a role to be used by concourse to deploy application builds.
  cat <<EOF > "build/${APP_NAME}-params.yml"
service-account-key: random-string
domain: ${APP_DOMAIN}
kubeconfig: |
  apiVersion: v1
  kind: Config
  clusters:
  - name: ${K8S_CLUSTER_NAME}
    cluster:
      certificate-authority-data: ${CA}
      server: ${SERVER}
  contexts:
  - name: default-context
    context:
      cluster: ${K8S_CLUSTER_NAME}
      namespace: default
      user: default-user
  current-context: default-context
  users:
  - name: default-user
    user:
      token: ${TOKEN}

app_manifest: |
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    labels:
      app: ${APP_NAME}
      source: freshcloud
    name: ${APP_NAME}
    namespace: ${APP_NAME}
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: ${APP_NAME}
    template:
      metadata:
        labels:
          app: ${APP_NAME}
      spec:
        containers:
        - image: CURRENT_APP_IMAGE
          name: ${APP_NAME}
          imagePullPolicy: Always
  ---
  apiVersion: v1
  kind: Service
  metadata:
    labels:
      app: ${APP_NAME}
    name: ${APP_NAME}
    namespace: ${APP_NAME}
  spec:
    ports:
    - port: 80
      protocol: TCP
      targetPort: 8080
    selector:
      app: ${APP_NAME}
    sessionAffinity: None
    type: ClusterIP
  ---
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: ${APP_NAME}
    namespace: ${APP_NAME}
    labels:
      app: ${APP_NAME}
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      kubernetes.io/ingress.class: contour
      ingress.kubernetes.io/force-ssl-redirect: "true"
      projectcontour.io/websocket-routes: "/"
      kubernetes.io/tls-acme: "true"
  spec:
    rules:
    - host: ${APP_NAME}.${APP_DOMAIN}
      http:
        paths:
        - backend:
            service:
              name: ${APP_NAME}
              port:
                number: 80
          pathType: ImplementationSpecific
    tls:
    - hosts:
      - ${APP_NAME}.${APP_DOMAIN}
      secretName: ${APP_NAME}-cert
EOF

  if [ -n "${DEPLOY_KEY}" ]; then
    KEY=$(< "${DEPLOY_KEY}" awk '{print "  " $0}')
    cat <<EOF >> "build/${APP_NAME}-params.yml"
git_repo_deploy_key: |
${KEY}
EOF
  fi
}

function write_pipeline() {

  echo "Writing pipeline yaml"
  cat <<EOF > "build/${APP_NAME}-pipeline.yml"
resource_types:
- name: kpack-image
  type: registry-image
  source:
    repository: harbor.markalston.net/concourse-images/concourse-kpack-resource
    tag: "1.0"

resources:
  - name: ${APP_NAME}-image
    type: registry-image
    source:
      repository: harbor.markalston.net/tanzu/${APP_NAME}

  - name: ${APP_NAME}-source-code
    type: git
    source:
      uri: ${APP_REPO}
      branch: ${APP_BRANCH}
EOF
if [ -n "${DEPLOY_KEY}" ]; then
cat <<EOF >> "build/${APP_NAME}-pipeline.yml"
      private_key: ((git_repo_deploy_key))
EOF
fi

cat <<EOF >> "build/${APP_NAME}-pipeline.yml"
  - name: ${APP_NAME}-build-service
    type: kpack-image
    source:
      image: "${APP_NAME}-image"
      namespace: ${APP_NAME}
      gke:
        json_key: ((service-account-key))
        kubeconfig: ((kubeconfig))

jobs:
  - name: vulnerability-scan
    plan:
    - task: sleep
      config:
        platform: linux
        image_resource:
          type: registry-image
          source:
            repository: ubuntu
            tag: bionic
        run:
          path: /bin/sleep
          args: [15s]
    - in_parallel:
      - get: ${APP_NAME}-build-service
        trigger: true
        passed: [build-${APP_NAME}-image]
      - get: ${APP_NAME}-image
    - task: trivy-fs
      config:
        platform: linux
        image_resource:
          type: registry-image
          source:
            repository: aquasec/trivy
        inputs:
        - name: ${APP_NAME}-image
        caches:
        - path: trivy-cache
        run:
          path: sh
          args:
          - -cex
          - |
            trivy --cache-dir trivy-cache fs --severity HIGH,CRITICAL --vuln-type library,os --ignore-unfixed --exit-code 1 ${APP_NAME}-image/rootfs


  - name: build-${APP_NAME}-image
    plan:
      - get: ${APP_NAME}-source-code
        trigger: true
        #     - task: run unit tests
        # file: source-code/pipeline/unit-test.yml
      - put: ${APP_NAME}-build-service
        params:
          commitish: ${APP_NAME}-source-code/.git/ref

  - name: deploy-${APP_NAME}
    plan:
      - get: ${APP_NAME}-source-code
      - get: ${APP_NAME}-build-service
        passed:
        - vulnerability-scan
        trigger: true
      - task: deploy-kubernetes
        config:
          platform: linux
          image_resource:
            type: registry-image
            source:
              repository: harbor.markalston.net/concourse-images/kubectl-docker
              tag: 1.20.7
          inputs:
            - name: ${APP_NAME}-source-code
          params:
            KUBECONFIG:
            MANIFEST:
            DOMAIN:
          run:
            path: sh
            args:
            - -ec
            - |
              echo "\$KUBECONFIG" > config.yml
              export KUBECONFIG=config.yml
              echo "\$MANIFEST" > ${APP_NAME}-deployment.yml
              IMG=\$(kubectl get images.kpack.io ${APP_NAME}-image -n ${APP_NAME} -o jsonpath="{.status.latestImage}")
              sed -i "s|CURRENT_APP_IMAGE|\$IMG|" ${APP_NAME}-deployment.yml
              kubectl apply -f ${APP_NAME}-deployment.yml
              echo "https://${APP_NAME}.${APP_DOMAIN}"
          platform: linux
        params:
          KUBECONFIG: ((kubeconfig))
          MANIFEST: ((app_manifest))
          DOMAIN: ((domain))
EOF
}

function fly_login() {
  cd ../../bosh || die "Couldn't change into bosh directory"

  eval "$(bbl print-env)"

  concourse_url=$(bosh int vars/concourse-vars-file.yml --path /external_url)
  username=$(bosh int vars/concourse-vars-file.yml --path /local_user/username)
  password=$(bosh int vars/concourse-vars-file.yml --path /local_user/password)

  cd - &> /dev/null || die "Couldn't change back into local directory"

  fly -t concourse login -c "$concourse_url" -u "$username" -p "$password" -k
}

function fly_pipeline() {
  fly_login
  echo y | fly -t "${TARGET}" set-pipeline -p "build-${APP_NAME}" -c "build/${APP_NAME}-pipeline.yml" -l "build/${APP_NAME}-params.yml"
  fly -t "${TARGET}" unpause-pipeline -p "build-${APP_NAME}"
}

function add_app() {

  # shellcheck source=apps/${APP_NAME}.sh
  # shellcheck disable=SC1091
  source "${1}"
  echo "Adding ${APP_NAME}"

  echo "Creating kubernetes namespace for ${APP_NAME}"
  kubectl create ns "${APP_NAME}" &> /dev/null

  create_secret_kpack

  if [ -n "${DEPLOY_KEY}" ]; then
    echo "Creating kpack secret for deploy key: ${APP_NAME}-deploy-key"
    kp secret create "${APP_NAME}-deploy-key" --git-url git@github.com --git-ssh-key "${DEPLOY_KEY}" -n "${APP_NAME}"
  fi

  create_service_account_kpack
  # create_builder_kpack
  create_app_image_spec
  install_role_binding
  write_pipeline_params
  write_pipeline
  yq e '.app_manifest' "build/${APP_NAME}-params.yml" > "build/${APP_NAME}-manifest.yml"

  echo "Deploying the pipeline to Concourse"
  fly_pipeline &> /dev/null

  echo ""
  echo "${APP_NAME} added succesfully!"
  echo "View the build progress with the below command."
  echo "  kp build logs ${APP_NAME}-image -n ${APP_NAME}"
}

function delete_app() {

  if [ ! -e "$1" ]; then
      echo "$1 doesn't seem to exist."
      exit 1
  fi
  # shellcheck source=apps/${APP_NAME}.sh
  # shellcheck disable=SC1091
  source "${1}"

  fly -t "${TARGET}" dp -p "build-${APP_NAME}"
  kubectl delete ns "${APP_NAME}"
  rm -f "build/${APP_NAME}-*.yml"
}

function list_apps() {
  for i in $(kubectl get deployments -A -l source=freshcloud | awk {'print $1}'|grep -v NAMESPACE); do
      kubectl get ingress -n $i 2> /dev/null|egrep -v 'NAME|acme-http' | awk {'printf ("%15s\t\t%s\n", $1, $3)'};
  done
}

function list_endpoints() {

  cat << EOF
Harbor: https://${REGISTRY}
user: admin
pass: ${REGISTRY_PASSWORD}

Concourse: https://${CONCOURSE}
user: admin
pass: ${CONCOURSE_PASSWORD}
EOF
}

TERM=dumb
TARGET=concourse
DOMAIN="${DOMAIN:-"example.com"}"
APP_DOMAIN="${APP_DOMAIN:-"tkg.$DOMAIN"}"
REGISTRY="${REGISTRY:-"registry.${DOMAIN}"}"
CONCOURSE="${CONCOURSE:-"concourse.${DOMAIN}"}"

# Options
if [ "$1" == 'endpoints' ]; then
    list_endpoints
elif [ "$1" == 'login' ]; then
    fly_login
elif [ "$1" == 'add' ]; then
  if [ -z "$2" ]; then
    echo "$0 add config.app"
    exit 1
  fi
  add_app "$2"
elif [ "$1" == 'delete' ]; then
  if [ -z "$2" ]; then
    echo "$0 delete config.app"
    exit 1
  fi
  delete_app "$2"
elif [ "$1" == 'apps' ]; then
  list_apps
else
  echo "freshctl manages fresh cloud applications."
  echo ""
  echo "Basic Commands:"
  echo "  $0 add                  add an application"
  echo "  $0 delete               delete an application"
  echo "  $0 endpoints            list endpoints"
  echo "  $0 apps                 list applications"
  echo
  exit 1
fi
