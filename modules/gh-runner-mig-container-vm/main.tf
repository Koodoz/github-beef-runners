locals {
  dindVolumeMounts = var.dind ? [{
    mountPath = "/var/run/docker.sock"
    name      = "dockersock"
    readOnly  = false
  }] : []
  dindVolumes = var.dind ? [
    {
      name = "dockersock"

      hostPath = {
        path = "/var/run/docker.sock"
      }
  }] : []
  network_name    = var.create_network ? google_compute_network.gh-network[0].self_link : var.network_name
  subnet_name     = var.create_network ? google_compute_subnetwork.gh-subnetwork[0].self_link : var.subnet_name
  service_account = var.service_account == "" ? google_service_account.runner_service_account[0].email : var.service_account
  # location   = var.regional ? var.region : var.zones[0]
}

/*****************************************
  Optional Runner Networking
 *****************************************/
resource "google_compute_network" "gh-network" {
  count                   = var.create_network ? 1 : 0
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "gh-subnetwork" {
  count         = var.create_network ? 1 : 0
  project       = var.project_id
  name          = var.subnet_name
  ip_cidr_range = var.subnet_ip
  region        = var.region
  network       = google_compute_network.gh-network[0].name
}

resource "google_compute_router" "default" {
  count   = var.create_network ? 1 : 0
  name    = "${var.network_name}-router"
  network = google_compute_network.gh-network[0].self_link
  region  = var.region
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  count                              = var.create_network ? 1 : 0
  project                            = var.project_id
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.default[0].name
  region                             = google_compute_router.default[0].region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}


/*****************************************
  IAM Bindings GCE SVC
 *****************************************/

resource "google_service_account" "runner_service_account" {
  count        = var.service_account == "" ? 1 : 0
  project      = var.project_id
  account_id   = "runner-service-account"
  display_name = "Github Runner GCE Service Account"
}

# allow GCE to pull images from GCR
resource "google_project_iam_binding" "gce" {
  count   = var.service_account == "" ? 1 : 0
  project = var.project_id
  role    = "roles/storage.objectViewer"
  members = [
    "serviceAccount:${local.service_account}",
  ]
}

/*****************************************
  Runner GCE Instance Template
 *****************************************/
locals {
  instance_name = format("%s-%s", var.instance_name, substr(md5(var.image), 0, 8))
}

module "gce-container" {
  for_each = var.runner_types

  source  = "terraform-google-modules/container-vm/google"
  version = "~> 3.0"
  container = {
    image = var.image
    env = [
      {
        name  = "ACTIONS_RUNNER_INPUT_URL"
        value = var.org_url
      },
      {
        name = "ACTIONS_RUNNER_INPUT_LABELS"
        value = each.key,
      },
      {
        name  = "GITHUB_TOKEN"
        value = var.gh_token
      },
      {
        name  = "ORG_NAME"
        value = var.org_name
      }
    ]

    # Declare volumes to be mounted
    # This is similar to how Docker volumes are mounted
    volumeMounts = concat([
      {
        mountPath = "/cache"
        name      = "tempfs-0"
        readOnly  = false
      }
    ], local.dindVolumeMounts)
  }

  # Declare the volumes
  volumes = concat([
    {
      name = "tempfs-0"

      emptyDir = {
        medium = "Memory"
      }
    }
  ], local.dindVolumes)

  restart_policy = var.restart_policy
}


module "mig_template" {
  for_each = var.runner_types

  source             = "terraform-google-modules/vm/google//modules/instance_template"
  version            = "~> 11.0"
  project_id         = var.project_id
  machine_type       = each.value.gcp_machine_type
  region             = var.region
  network            = local.network_name
  subnetwork         = local.subnet_name
  subnetwork_project = var.subnetwork_project != "" ? var.subnetwork_project : var.project_id
  service_account = {
    email = local.service_account
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
  disk_size_gb         = 100
  disk_type            = "pd-ssd"
  auto_delete          = true
  name_prefix          = "gh-runner-${each.value.name_suffix}"
  source_image_family  = "cos-stable"
  source_image_project = "cos-cloud"
  startup_script       = "export TEST_ENV='hello'"
  source_image         = reverse(split("/", module.gce-container[each.key].source_image))[0]
  metadata             = merge(var.additional_metadata, { "gce-container-declaration" = module.gce-container[each.key].metadata_value })
  spot                 = each.value.is_spot_instance
  tags = [
    "gh-runner-vm"
  ]
  labels = {
    container-vm = module.gce-container[each.key].vm_container_label
  }
}
/*****************************************
  Runner MIG
 *****************************************/
# Create a Managed Instance Group for each instance of the runner_types map
module "mig" {
  for_each = var.runner_types

  source             = "terraform-google-modules/vm/google//modules/mig"
  version            = "~> 11.0"
  project_id         = var.project_id
  hostname           = "${local.instance_name}-${each.key}"
  region             = var.region
  instance_template  = module.mig_template[each.key].self_link # module.mig_template.self_link

  /* autoscaler */
  autoscaling_enabled = true
  autoscaling_mode    = "metric"
  autoscaling_metric  = tolist([{
    name   = google_monitoring_metric_descriptor.metric_required_runner_count.type
    target = 1 
    type   = "GAUGE"
  }])
  min_replicas        = each.value.min_replicas
  max_replicas        = each.value.max_replicas
  cooldown_period     = var.cooldown_period
}


/*****************************************
  Github Runner Webhook Cloud Function
 *****************************************/
resource "random_id" "default" {
  byte_length = 8
}

locals {
  function_source_dir = "${path.module}/function-process-webhook"
}

data "archive_file" "webhook" {
  type        = "zip"

  # We use the md5 of the index.js file to generate a unique name for the zip file to force re-zipping of the contents 
  # when the source changes
  output_path = "/tmp/beef-process-webhook-${filemd5("${local.function_source_dir}/index.js")}.zip"
  source_dir  = local.function_source_dir
  excludes    = tolist(["index.test.js"])
}

resource "google_storage_bucket" "functions" {
  name     = "beef-runner-${random_id.default.hex}-cloudfunction-source"
  location = "US"
  project  = var.project_id
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "sourcecode" {
  name   = "process-webhook-function-source.zip"
  bucket = google_storage_bucket.functions.name
  source = data.archive_file.webhook.output_path # Add path to the zipped function source code
}

resource "google_monitoring_metric_descriptor" "metric_required_runner_count" {
  project         = var.project_id
  description     = "The number of required runners needed to fulfill all current Github jobs"
  display_name    = "metric-required-runner-count"
  type            = "custom.googleapis.com/beef_github_runner/required_runner_count"
  metric_kind     = "GAUGE"
  value_type      = "INT64"
  metadata {
    sample_period = "5s"
    ingest_delay  = "1s"
  }
}

resource "google_cloudfunctions2_function" "fn_process_webhook" {
  name        = "fn-process-webhook"
  location    = var.region 
  project     = var.project_id
  description = "A function to process Github Webhooks for the Beef Runner. It's primarily used to trigger the autoscaler so that the runner can scale up or down based on the number of jobs in the queue."

  build_config {
    runtime     = "nodejs20"
    entry_point = "processGithubRunnerWebhook"
    source {
      storage_source {
        bucket = google_storage_bucket.functions.name
        object = google_storage_bucket_object.sourcecode.name
      }
    }
  }

  service_config {
    available_cpu       = "0.5"
    available_memory   = "128Mi"
    timeout_seconds    = 60
    environment_variables = {
      PROJECT_ID              = var.project_id
      STACKDRIVER_METRIC_NAME = google_monitoring_metric_descriptor.metric_required_runner_count.type
      GITHUB_WEBHOOK_SECRET   = var.gh_webhook_secret

      # Causes a re-deploy of the function when the source changes
      VERSION_SHA             = data.archive_file.webhook.output_sha
    }
    ingress_settings = "ALLOW_ALL"
  }

  lifecycle {
    replace_triggered_by  = [
      google_storage_bucket_object.sourcecode
    ]
  }
}

# Allow all users to invoke the Cloud Run service
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  project     = google_cloudfunctions2_function.fn_process_webhook.project
  location    = google_cloudfunctions2_function.fn_process_webhook.location
  service     = google_cloudfunctions2_function.fn_process_webhook.name

  policy_data = data.google_iam_policy.noauth.policy_data
}
