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
  description = "The project id to deploy Github Runner Managed Instance Group (MIG)"
}

variable "region" {
  type        = string
  description = "The region to deploy Github Runner Managed Instance Group (MIG)"
  default = "us-central1"
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
}

variable "runner_types" {
  type = map(object({
    name_suffix = string
    gcp_machine_type = string
  }))
  description = "The types of runners to create. It allows users to quickly create multiple types of runners"
}
