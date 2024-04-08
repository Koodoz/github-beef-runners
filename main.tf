/**
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

module "runner-mig-dind" {
  source  = "./modules/gh-runner-mig-container-vm"

  create_network    = true
  project_id        = var.project_id
  image             = var.image
  org_name          = var.org_name
  org_url           = var.org_url
  gh_token          = var.gh_token
  gh_webhook_secret = var.gh_webhook_secret
  runner_types      = var.runner_types
  region            = var.region
  dind              = true
}
