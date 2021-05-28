/**
 * Copyright 2021 Google LLC
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

locals {
  account_billing       = var.grant_billing_role && var.billing_account_id != ""
  org_billing           = var.grant_billing_role && var.billing_account_id == "" && var.org_id != ""
  prefix                = var.prefix != "" ? "${var.prefix}-" : ""
  xpn                   = var.grant_xpn_roles && var.org_id != ""
  service_accounts_list = [for name in var.names : google_service_account.service_accounts[name]]
  emails_list           = [for account in local.service_accounts_list : account.email]
  iam_emails_list       = [for email in local.emails_list : "serviceAccount:${email}"]
  names                 = toset(var.names)
  name_role_pairs       = setproduct(local.names, toset(var.project_roles))
  project_roles_map_data = zipmap(
    [for pair in local.name_role_pairs : "${pair[0]}-${pair[1]}"],
    [for pair in local.name_role_pairs : {
      name = pair[0]
      role = pair[1]
    }]
  )
  org_role_pairs = setproduct(local.names, toset(var.org_roles))
  org_roles_map_data = zipmap(
    [for pair in local.org_role_pairs : "${pair[0]}-${pair[1]}"],
    [for pair in local.org_role_pairs : {
      name = pair[0]
      role = pair[1]
    }]
  )
  billing_account_role_pairs = setproduct(local.names, toset(var.billing_user_roles))
  billing_account_roles_map_data = zipmap(
    [for pair in local.billing_account_role_pairs : "${pair[0]}-${pair[1]}"],
    [for pair in local.billing_account_role_pairs : {
      name = pair[0]
      role = pair[1]
    }]
  )
}

# create service accounts
resource "google_service_account" "service_accounts" {
  for_each     = local.names
  account_id   = "${local.prefix}${lower(each.value)}"
  display_name = var.display_name
  description  = var.description
  project      = var.project_id
}

# Project level permissions.
resource "google_project_iam_member" "project-roles" {
  for_each = local.project_roles_map_data

  project = element(
    split(
      "=>",
      each.value.role
    ),
    0,
  )

  role = element(
    split(
      "=>",
      each.value.role
    ),
    1,
  )

  member = "serviceAccount:${google_service_account.service_accounts[each.value.name].email}"
}

# Organization level permissions. 
resource "google_organization_iam_member" "billing_user" {
  for_each = local.billing_account_roles_map_data
  org_id   = var.org_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.service_accounts[each.value.name].email}"
}

# Billing permissions.
resource "google_organization_iam_member" "organization_viewer" {
  for_each = local.org_roles_map_data
  org_id   = var.org_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.service_accounts[each.value.name].email}"
}

# keys
resource "google_service_account_key" "keys" {
  for_each           = var.generate_keys ? local.names : toset([])
  service_account_id = google_service_account.service_accounts[each.value].email
}
