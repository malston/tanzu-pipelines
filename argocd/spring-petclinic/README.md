# Kustomize Application

## Prerequisites

Install the following tools

- [pack](https://github.com/buildpacks/pack)
- [kustomize](https://kustomize.io/)

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

## Update image to the latest digest reference

1. Get the image you want to use in your manifest

    ```sh
    LATEST_IMAGE=$(kubectl get image spring-petclinic-image -n spring-petclinic -o jsonpath="{.status.latestImage}")
    ```

1. Then, go into the directory where the `kustomization.yaml` and `deployment.yaml` is
for the application you want to deploy

    ```sh
    cd argocd/spring-petclinic/production
    ```

1. Set the image using `kustomize` to the image retrieved in the first step above

    ```sh
    kustomize edit set image "$LATEST_IMAGE"
    ```
