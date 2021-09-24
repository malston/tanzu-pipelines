# Kustomize Application

## Build/Run locally

```sh
cd ~/workspace/kotlin-sample-app
pack build applications/kotlin
docker run --rm --tty --publish 8080:8080 applications/kotlin
curl -s http://localhost:8080/actuator/health | jq .
```

## Tag/Push to registry

Docker:

```sh
docker tag applications/kotlin:latest registry.pez.joecool.cc/kpack/kotlin-sample-app:0.0.1
docker tag applications/kotlin:latest malston/kotlin-sample-app:0.0.1
```

Private Registry:

```sh
docker push malston/kotlin-sample-app:0.0.1
docker push registry.pez.joecool.cc/kpack/kotlin-sample-app:0.0.1
```

## Update the digest reference on production image

```sh
cd ~/workspace/tanzu-pipelines
kustomize build argocd/kotlin-sample-app/production | kbld -f -
```
