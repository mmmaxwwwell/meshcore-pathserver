# infra

OpenTofu for everything on Cloudflare: the R2 data bucket, the Pages project
(with its R2 binding), the custom domain and its DNS record. CI applies it on
every push to `main` (`.forgejo/workflows/ci.yml` job `deploy`, via
`ci/infra.sh apply`, only after the secret-free scan gate passed); branch
pushes get a plan. Nobody runs `apply` by hand.

State is in R2 (`meshcore-paths-tfstate`, S3 backend, native lockfile) and
encrypted with OpenTofu's state encryption (pbkdf2 passphrase). It is never
committed.

## Bootstrap (once per account)

These are the only steps outside OpenTofu: they create what OpenTofu itself
needs to run.

1. Enable R2 on the account (dashboard -> R2; accepts R2's terms).
2. Create the state bucket: `wrangler r2 bucket create meshcore-paths-tfstate`.
3. Create an R2 API token with Object Read & Write on that bucket only; its
   S3 access key id / secret become `R2_STATE_ACCESS_KEY_ID` /
   `R2_STATE_SECRET_ACCESS_KEY`.
4. Create a Cloudflare API token (custom): Account › Cloudflare Pages: Edit,
   Account › Workers R2 Storage: Edit, Zone › DNS: Edit and Zone › Zone: Read
   for the site's zone only. It becomes `CLOUDFLARE_API_TOKEN`.
5. Generate the state passphrase (`openssl rand -base64 32`) into
   `TF_STATE_PASSPHRASE`, and keep an escrow copy: losing it loses the state
   (recoverable by re-importing, but avoid that).
6. Set `CLOUDFLARE_ACCOUNT_ID` and the four values above as Actions secrets.

## Local plan (optional)

```bash
export CLOUDFLARE_API_TOKEN=... AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...
export TF_VAR_account_id=... TF_VAR_state_passphrase=...
nix develop .. -c tofu init -backend-config='endpoints={s3="https://<account id>.r2.cloudflarestorage.com"}'
nix develop .. -c tofu plan
```
