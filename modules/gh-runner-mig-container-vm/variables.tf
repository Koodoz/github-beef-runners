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

variable "project_id" {
  type        = string
  description = "The project id to deploy Github Runner"
}
variable "region" {
  type        = string
  description = "The GCP region to deploy instances into"
}

variable "network_name" {
  type        = string
  description = "Name for the VPC network"
  default     = "gh-runner-network"
}

variable "create_network" {
  type        = bool
  description = "When set to true, VPC,router and NAT will be auto created"
  default     = true
}

variable "subnetwork_project" {
  type        = string
  description = "The ID of the project in which the subnetwork belongs. If it is not provided, the project_id is used."
  default     = ""
}

variable "subnet_ip" {
  type        = string
  description = "IP range for the subnet"
  default     = "10.10.10.0/24"
}
variable "subnet_name" {
  type        = string
  description = "Name for the subnet"
  default     = "gh-runner-subnet"
}

variable "restart_policy" {
  type        = string
  description = "The desired Docker restart policy for the runner image"
  default     = "Always"
}

variable "image" {
  type        = string
  description = "The github runner image"
}

variable "org_url" {
  type        = string
  description = "Organization URL for the Github Action"
}

variable "org_name" {
  type        = string
  description = "Name of the Organization for which the Github Action Runner will be registered to"
}

variable "gh_token" {
  type        = string
  description = "Github token that is used for generating Self Hosted Runner Token"
  sensitive   = true
}

variable "gh_webhook_secret" {
  type        = string
  description = "The Secret passed by the Github webhook which will be used to validate the incoming request"
  sensitive   = true
}

variable "instance_name" {
  type        = string
  description = "The gce instance name"
  default     = "gh-runner"
}

variable "runner_types" {
  type = map(object({
    name_suffix = string
    gcp_machine_type = string
    is_spot_instance = bool
    min_replicas = number
    max_replicas = number
  }))
  description = "The types of runners to create. It allows users to quickly create multiple types of runners"
}

variable "service_account" {
  description = "Service account email address"
  type        = string
  default     = ""
}
variable "additional_metadata" {
  type        = map(any)
  description = "Additional metadata to attach to the instance"
  default     = {}
}

variable "dind" {
  type        = bool
  description = "Flag to determine whether to expose dockersock "
  default     = false
}

variable "cooldown_period" {
  description = "The number of seconds that the autoscaler should wait before it starts collecting information from a new instance."
  type        = number
  default     = 60
}
