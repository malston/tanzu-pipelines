# Kustomize Application

## Build/Run locally

```sh
cd ~/workspace/kotlin-sample-app
pack build applications/kotlin
docker run --rm --tty --publish 8080:8080 applications/kotlin
curl -s http://localhost:8080/actuator/health | jq .
```

## Tag/Push to registry

to Docker:

```sh
docker tag applications/kotlin:latest malston/kotlin-sample-app:0.0.1
docker push malston/kotlin-sample-app:0.0.1
```

to Private Registry:

```sh
docker tag applications/kotlin:latest registry.example.com/kpack/kotlin-sample-app:0.0.1
docker push registry.example.com/kpack/kotlin-sample-app:0.0.1
```

## Update the digest reference on production image

View change first

```sh
cd ~/workspace/tanzu-pipelines
kustomize build argocd/kotlin-sample-app/production | kbld -f -
```

Update using `yq` and `kbld`

```sh
cd ~/workspace/tanzu-pipelines
CURRENT_APP_IMAGE=$(yq e .spec.template.spec.containers[0].image argocd/kotlin-sample-app/production/deployment.yaml)
IMAGE=$(kustomize build argocd/kotlin-sample-app/production | kbld -f - | grep -e 'image:' | awk '{print $NF}')
sed -i "s|$CURRENT_APP_IMAGE|$IMAGE|" argocd/kotlin-sample-app/production/deployment.yaml
```
