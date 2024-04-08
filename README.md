# Github Beef Runners 🥩
Tool to host Github Actions Runners in GCP

## "Beef" Runners? Where's the beef?

The standard runners provided by Github are limited in terms of resources and can be slow for some workloads. Even when you scale up, you're paying a lot and you're not getting any "beefy" performance.

The name is inspired by this [classic commercial](https://www.youtube.com/watch?v=u0aKKFybRNM).

By allowing you to host your own Github runners in GCP for a fraction of the cost, you can get the beefy performance you need.

### A note on autoscaling

Since we are directly running on instances instead of through Kubernetes, we can't use something like [ARC](https://github.com/actions/actions-runner-controller). Instead, for autoscaling, we are going to rely on [simple metrics based autoscaling](https://cloud.google.com/compute/docs/autoscaler/scaling-cloud-monitoring-metrics#configure_autoscaling_based_on_metrics).

We will do the following:

1. Register a custom metric in GCP that will be used to determine the number of runners needed. This will be a simple gauge that will equal running count + pending jobs count. 
2. Register a API Gateway wired up to a Cloud Function that will update the metric based off Github webhooks.
3. Create a autoscaler that will scale up and down based off the metric.


## Installation

1. Repoint your GCloud SDK to the desired project and enable the necessary APIs:
   ```bash
   gcloud config set project <gcp-project-id>

   # Enable the necessary APIs
   # - Container Registry + Cloudbuild APIs are required for Docker image building
   # - Compute Engine API is required for creating the VMs
   gcloud services enable containerregistry.googleapis.com cloudbuild.googleapis.com compute.googleapis.com
   ```

2. Build the Docker image via cloudbuild: `gcloud builds submit --config=cloudbuild.yaml runner/`

3. Create a `terraform.tfvars` file with the following content:
   ```hcl
   project_id = "<gcp-project-id>"
   image      = "<docker-image-url:tag>" # e.g. gcr.io/<gcp-project-id>/gcp-github-actions:latest
   gh_token   = "<your-github-classic-token>"
   org_url    = "https://github.com/<org-name>"
   org_name   = "<org-name>"
   runner_types = {
     "<runner-alias>" = {
       name_suffix = "<runner-name-suffix>"
       gcp_machine_type = "<gcp-machine-type>" # e.g. 'n1-standard-2'
     }
   }
   ```
4. Run `terraform init`, `terraform plan` and if everything looks good.. `terraform apply` to deploy the infrastructure.
