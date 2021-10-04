# Tanzu Pipelines

## Demo

1. Dev Concourse pipeline
    1. Explain the stages of the pipeline
        1. Image is built using Tanzu Build Service / Kpack and stored in a Private Registry
        2. Image is pulled down from Registry and Scanned for vulnerabilities
        3. App is deployed automatically to a dev namespace
    2. Show the `kustomize` deployment manifests
    3. Change the application running on workstation
        1. Once a Developer is ready to push their changes to Github, they first run `pack`, and test it locally
        2. Make a commit and push to Github
    4. Show that the pipeline is triggered and wait for it to get through the build phase
    5. Grab the commit that passed the scanning stage
        1. `kubectl get image spring-petclinic-image -n spring-petclinic -o jsonpath="{.status.latestImage}"`
        2. Switch over to the `tanzu-pipelines` code and update the `Deployment` image. Push that commit.
    6. Watch ArgoCD automatically sync the change and update the deployed application.

2. Prod Concourse pipeline
    1. Explain the stages of the pipeline
        1. Install is only run once to create the Application in ArgoCD but is NOT set to automatically sync
        2. Sync is run manually when ready to deploy to production
    2. Update production deployment manifest to match latest `kpack` image that passed CI
    3. Run the sync app job when ready to deploy and explain the `sync-and-wait` task.
