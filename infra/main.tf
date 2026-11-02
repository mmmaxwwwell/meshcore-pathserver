data "cloudflare_zone" "site" {
  filter = {
    name = var.zone
  }
}

resource "cloudflare_r2_bucket" "data" {
  account_id = var.account_id
  name       = var.data_bucket
}

# Direct-upload project: CI builds the site and runs `wrangler pages deploy`.
# The R2 binding lives here, not in a wrangler.toml, so this file is the one
# source of truth for the project's configuration.
resource "cloudflare_pages_project" "site" {
  account_id        = var.account_id
  name              = var.project_name
  production_branch = "main"

  deployment_configs = {
    production = {
      compatibility_date = "2026-11-01"
      r2_buckets = {
        DATA = { name = cloudflare_r2_bucket.data.name }
      }
    }
    preview = {
      compatibility_date = "2026-11-01"
    }
  }
}

# The project was first created by hand (2026-11-01) before this config existed.
import {
  to = cloudflare_pages_project.site
  id = "${var.account_id}/${var.project_name}"
}

resource "cloudflare_pages_domain" "site" {
  account_id   = var.account_id
  project_name = cloudflare_pages_project.site.name
  name         = var.hostname
}

resource "cloudflare_dns_record" "site" {
  zone_id = data.cloudflare_zone.site.zone_id
  name    = var.hostname
  type    = "CNAME"
  content = cloudflare_pages_project.site.subdomain
  proxied = true
  ttl     = 1
  comment = "MeshCore Paths (Pages), managed by OpenTofu in meshcore-pathserver/infra"
}

output "url" {
  value = "https://${var.hostname}"
}
