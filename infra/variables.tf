variable "account_id" {
  description = "Cloudflare account id."
  type        = string
}

variable "zone" {
  description = "DNS zone the site lives under."
  type        = string
  default     = "mmmaxwwwell.dev"
}

variable "hostname" {
  description = "Public hostname of the site."
  type        = string
  default     = "paths.mmmaxwwwell.dev"
}

variable "project_name" {
  description = "Cloudflare Pages project (also the *.pages.dev subdomain)."
  type        = string
  default     = "meshcore-paths"
}

variable "data_bucket" {
  description = "R2 bucket the observers publish snapshots to; bound to the site's functions as DATA."
  type        = string
  default     = "meshcore-paths-data"
}

variable "state_passphrase" {
  description = "Encrypts the OpenTofu state and plans (pbkdf2). At least 16 characters."
  type        = string
  sensitive   = true
}
