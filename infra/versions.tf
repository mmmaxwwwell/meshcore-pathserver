terraform {
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.19"
    }
  }

  # State lives in R2, never in git. Endpoint and credentials come from CI
  # (-backend-config, AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY = an R2 API
  # token scoped to the state bucket). See infra/README.md "Bootstrap".
  backend "s3" {
    bucket                      = "meshcore-paths-tfstate"
    key                         = "site/terraform.tfstate"
    region                      = "auto"
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  # The state holds resource ids, not secrets, but encrypt it anyway: the
  # bucket is one leaked R2 key away from public.
  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }
    state {
      method   = method.aes_gcm.state
      enforced = true
    }
    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}

provider "cloudflare" {
  # CLOUDFLARE_API_TOKEN from the environment (CI secret).
}
