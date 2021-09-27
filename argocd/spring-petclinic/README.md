# Kustomize Application

## Prerequisites

Install the following tools

- [pack](https://github.com/buildpacks/pack)
- [kbld](https://carvel.dev/kbld/)
- [yq](https://github.com/mikefarah/yq)

## Build/Run locally

Build the app using `pack`:

```sh
git clone https://github.com/malston/spring-petclinic-tanzu.git
cd spring-petclinic-tanzu
pack build applications/maven
```

Test locally with Docker

```sh
docker run --rm --tty --publish 8080:8080 applications/maven
curl -s http://localhost:8080/actuator/health | jq .
```

## Tag/Push to registry

to Docker:

```sh
docker tag applications/maven:latest malston/spring-petclinic-tanzu:0.0.1
docker push malston/spring-petclinic-tanzu:0.0.1
```

to Private Registry:

```sh
docker tag applications/maven:latest registry.example.com/kpack/spring-petclinic-tanzu:0.0.1
docker push registry.example.com/kpack/spring-petclinic-tanzu:0.0.1
```

## Update the digest reference on production image

View change first

```sh
kustomize build argocd/spring-petclinic/production | kbld -f -
```

Update using `yq` and `kbld`

```sh
CURRENT_APP_IMAGE=$(yq e .spec.template.spec.containers[0].image argocd/spring-petclinic/production/deployment.yaml)
LATEST_IMAGE=$(kustomize build argocd/spring-petclinic/production | kbld -f - | grep -e 'image:' | awk '{print $NF}')
sed -i "s|$CURRENT_APP_IMAGE|$LATEST_IMAGE|" argocd/spring-petclinic/production/deployment.yaml
```

Or using `kustomize`

```sh
LATEST_IMAGE=$(kubectl get image "$APP_NAME-image" -n "$APP_NAME" -o jsonpath="{.status.latestImage}")
cd argocd/spring-petclinic/dev
kustomize edit set image "$LATEST_IMAGE"
```
