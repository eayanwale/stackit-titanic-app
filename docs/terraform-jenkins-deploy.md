# Terraform + Jenkins Deployment

Provisions the three-tier Titanic Survival stack described in
[`DEPLOYMENT.md`](../titanic-survival/DEPLOYMENT.md) with Terraform, driven by a Jenkins pipeline.

## Architecture

```
Internet -> ALB :80 (public subnets)
              -> ASG of EC2 + gunicorn :8000 (private subnets, NAT for outbound)
                   -> RDS Postgres 16 (private subnets)
                   -> SageMaker endpoint (optional; mock scoring when unset)
```

| File | Purpose |
|---|---|
| `terraform/network.tf` | Two private subnets, NAT gateway, private route table |
| `terraform/security.tf` | ALB, app and DB security groups (ALB -> 8000 -> 5432 chain) |
| `terraform/iam.tf` | Instance role: SSM parameters, optional `InvokeEndpoint`, Session Manager |
| `terraform/rds.tf` | Postgres in the private subnets |
| `terraform/ec2.tf` | Launch template (newest golden AMI) + ASG (rolling refresh on new AMI) + CPU scaling |
| `terraform/alb.tf` | ALB, target group (health check `/healthz`), HTTP listener |
| `terraform/user-data.tftpl` | Instance boot: read secrets from SSM, write `.env`, start the service |
| `packer/` | Golden image: AL2023 + Python 3.11 + the app and its pinned venv + systemd unit |
| `Jenkins_CI/Jenkinsfile` | Terraform deploy pipeline |
| `Jenkins_CI/Jenkinsfile-image` | Golden image build pipeline |

## Secrets (SSM Parameter Store)

Create these as `SecureString` parameters before the first apply. Nothing is stored in code.

| Parameter | Used by |
|---|---|
| `/stack/titanic/SECRET_KEY` | Flask session signing, read by the instance at boot |
| `/stack/titanic/APP_PASSWORD` | Seeded sign-in password, read by the instance at boot |
| `/stack/titanic/DB_PASSWORD` | RDS master password; Terraform reads it to create the DB and the instance reads it at boot |

The prefix is the `SSM_PREFIX` variable. The RDS master password cannot contain `/`, `@`, `"` or spaces.
The DB password is also stored in Terraform state because it is an RDS argument, so keep the state bucket private and encrypted.

## Deploy

1. Create the three SSM parameters above.
2. Run the image job (`Jenkins_CI/Jenkinsfile-image`). It runs the AI audit, then `packer init`, `validate` and `build`, and reports the new `stack-titanic-app-<timestamp>` AMI. Jenkins runs in the automation account, so the AMI and its snapshot are shared with the dev account (`aws_accounts` in the Packer template) and Terraform looks it up by `AMI_OWNER_ACCOUNT_ID`. The first apply needs at least one AMI to exist.
3. Run the deploy job (`Jenkins_CI/Jenkinsfile`) with `ACTION=apply`. It runs the AI audit, then `terraform init`, `plan` and `apply`.
4. Wait a couple of minutes for the first instance to boot, then open the `app_url` output (the ALB DNS name).
5. Sign in as `admin` with the `APP_PASSWORD` value.

Code changes: merge, run the image job, then the deploy job. The launch template picks up the newest AMI and the ASG rolls instances over.

Run locally instead with `terraform init`, `plan`, `apply` from `terraform/` using the `stackprog-dev` profile.
State is in `s3://enoch-tf-state-bucket/stackit-titanic-app/terraform.tfstate`.

## Jenkins

- Two Pipeline jobs: deploy with Script Path `Jenkins_CI/Jenkinsfile`, image with `Jenkins_CI/Jenkinsfile-image`. The agent needs `packer` at `/usr/bin/packer`.
- Credentials: `Claude_API`, `GITHUB_TOKEN`. Slack and the `stackprog-dev` AWS profile must be available on the agent.
- Each pipeline's AI audit is scoped to its own files with its own prompts in `Jenkins_CI/`. The deploy audit only looks at `terraform/` (secrets and `*.tf` syntax). The image audit looks at `packer/` (`*.pkr.hcl` and `*.sh` syntax) and scans `packer/` and `titanic-survival/` for secrets, because the app is baked into the AMI. Neither touches the other's files.
- Both pause for approval if secrets are found, then propose fixes that are only applied after a second approval and opened as a PR against `main`.
- `ACTION=destroy` skips the audit and tears the stack down.

## SageMaker endpoint

`SAGEMAKER_ENDPOINT_NAME` defaults to empty, so the app scores with its local heuristic and the result page shows "mock".
Once an endpoint exists, apply with `-var SAGEMAKER_ENDPOINT_NAME=<name>` (or change the default). That also creates the `InvokeTitanicEndpoint` policy.

## Cost

The NAT gateway, ALB, RDS and instance all bill hourly. Run `ACTION=destroy` when finished.

## Not yet in place

HTTPS (ACM certificate, 443 listener, Route 53 record) was deliberately left out for now.
