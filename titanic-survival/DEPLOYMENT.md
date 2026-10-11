# Deploying Titanic Survival on AWS — a three-tier architecture

This guide stands the app up on AWS as three separated tiers, then points it at
the SageMaker endpoint you trained in the model-training note.

```
        Internet
           │
   ┌───────▼────────┐   TIER 1 · presentation / edge
   │  Application    │   Application Load Balancer (HTTPS via ACM)
   │  Load Balancer  │   public subnets
   └───────┬────────┘
           │  :8000  (only the ALB security group may reach the app)
   ┌───────▼────────┐   TIER 2 · application logic
   │   EC2 + gunicorn│   the Flask app; IAM instance role can InvokeEndpoint
   │   (private subnet)│  runs feature engineering, calls the model
   └───┬───────────┬─┘
       │           │
 ┌─────▼────┐  ┌───▼──────────────┐   TIER 3 · data / model
 │   RDS    │  │ SageMaker endpoint│  user store (sign-in) + the deployed
 │ Postgres │  │  titanic-endpoint │  AutoML model that returns predictions
 └──────────┘  └──────────────────┘
```

Values below reuse the training note's account (`709143748493`), Region
(`us-east-1`), and endpoint (`titanic-endpoint`). Change them to yours.

> **SageMaker, not Bedrock.** This app queries your **SageMaker** AutoML
> endpoint. Amazon Bedrock hosts foundation models (text/image); it does not
> serve a tabular Autopilot model like this one, so the prediction call goes to
> SageMaker Runtime.

---

## 0 · Prerequisites

- The **SageMaker endpoint is InService** (from the training note, Part 08/11).
  Confirm: `aws sagemaker describe-endpoint --region us-east-1 --endpoint-name titanic-endpoint --query EndpointStatus`.
- AWS CLI configured for account `709143748493`.
- This project's files, and a VPC with public + private subnets (the **default
  VPC** is fine for a first deployment).
- Set your variables once:

```bash
export REGION="us-east-1"
export ACCOUNT_ID="709143748493"
export ENDPOINT="titanic-endpoint"
export APP_NAME="titanic-survival"
```

---

## 1 · Tier 2 identity — an IAM role the app runs as

The app must be allowed to call **one** endpoint — nothing more. Create a role
EC2 can assume, with a least-privilege invoke policy.

```bash
# trust policy: EC2 may assume this role
cat > app-trust.json << 'JSON'
{ "Version":"2012-10-17",
  "Statement":[{ "Effect":"Allow",
    "Principal":{"Service":"ec2.amazonaws.com"},
    "Action":"sts:AssumeRole" }] }
JSON

aws iam create-role --role-name "${APP_NAME}-role" \
  --assume-role-policy-document file://app-trust.json

# least-privilege: invoke only this endpoint
cat > app-invoke.json << JSON
{ "Version":"2012-10-17",
  "Statement":[{ "Effect":"Allow",
    "Action":"sagemaker:InvokeEndpoint",
    "Resource":"arn:aws:sagemaker:${REGION}:${ACCOUNT_ID}:endpoint/${ENDPOINT}" }] }
JSON

aws iam put-role-policy --role-name "${APP_NAME}-role" \
  --policy-name InvokeTitanicEndpoint --policy-document file://app-invoke.json

# instance profile that carries the role onto the EC2 host
aws iam create-instance-profile --instance-profile-name "${APP_NAME}-profile"
aws iam add-role-to-instance-profile \
  --instance-profile-name "${APP_NAME}-profile" --role-name "${APP_NAME}-role"
```

---

## 2 · Tier 3 (optional) — RDS for the user store

For a demo the app uses SQLite (zero setup). For production, create a small
Postgres instance and point the app at it with `DATABASE_URL`.

```bash
aws rds create-db-instance --region "$REGION" \
  --db-instance-identifier "${APP_NAME}-db" \
  --engine postgres --db-instance-class db.t3.micro \
  --allocated-storage 20 --master-username titanic \
  --master-user-password 'ChangeThisPassword1' \
  --db-name titanic --no-publicly-accessible
```

When it's available, the connection string is:
`postgresql://titanic:ChangeThisPassword1@<rds-endpoint>:5432/titanic`
(You'll also need `pip install psycopg2-binary` in the app venv.)

---

## 3 · Tier 2 — launch the app host

1. **Launch an EC2 instance** (Amazon Linux 2023, `t3.small`) in a subnet, and
   **attach the instance profile** `titanic-survival-profile` from Step 1.
2. **Security group** `app-sg`: allow inbound TCP **8000 from the ALB security
   group only** (Step 4), and SSH (22) from your IP for setup.
3. SSH in and install the app:

```bash
sudo dnf install -y python3.11 git
sudo mkdir -p /opt/titanic-survival && sudo chown ec2-user /opt/titanic-survival
# copy the project up (scp, git clone, or an S3 sync), then:
cd /opt/titanic-survival
python3.11 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
```

4. **Environment file** `/opt/titanic-survival/.env` (systemd reads it):

```bash
SECRET_KEY=<a-long-random-string>
APP_USERNAME=admin
APP_PASSWORD=<pick-a-real-password>
AWS_REGION=us-east-1
SAGEMAKER_ENDPOINT_NAME=titanic-endpoint
# DATABASE_URL=postgresql://titanic:...@<rds-endpoint>:5432/titanic
```

5. **Run it under systemd** with gunicorn. Create `/etc/systemd/system/titanic.service`:

```ini
[Unit]
Description=Titanic Survival
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/titanic-survival
EnvironmentFile=/opt/titanic-survival/.env
ExecStart=/opt/titanic-survival/.venv/bin/gunicorn -w 3 -b 0.0.0.0:8000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now titanic
curl -s localhost:8000/healthz     # -> {"status":"ok"}
```

---

## 4 · Tier 1 — the load balancer (edge)

1. **Target group** `titanic-tg`: protocol HTTP, **port 8000**, health-check
   path **`/healthz`**. Register your EC2 instance.
2. **Security group** `alb-sg`: allow inbound **80** and **443** from the
   internet. (Then confirm `app-sg` allows 8000 *from `alb-sg`*.)
3. **Application Load Balancer** `titanic-alb` in two public subnets, with a
   listener on **80** forwarding to `titanic-tg`.
4. **HTTPS (recommended):** request a certificate in **ACM**, add a **443**
   listener using it, and redirect 80 → 443.

The app is now reachable at the ALB's DNS name (and your custom domain if you
pointed one at it in Route 53).

---

## 5 · Verify end to end

```bash
# from anywhere
curl -s http://<alb-dns-name>/healthz      # {"status":"ok"}
```

Then in a browser: open the ALB URL → sign in (`admin` / your password) →
enter a passenger → **Predict survival**. The result page's footer should read
**"Scored by the SageMaker endpoint"** (a teal dot), confirming the app reached
the model rather than the local heuristic.

---

## 6 · Show a real probability on the gauge

By default an Autopilot classification endpoint returns just the predicted
label (`0`/`1`). To make the gauge show a true probability, configure the
endpoint's model to also return the **positive-class probability**, then the
app parses `label,probability` automatically. You set this when creating the
model from the best candidate by adding the inference response keys — e.g. in
the SDK, `inference_response_keys=["predicted_label", "probability"]` — or
select "probability" in the Studio deploy dialog. Until then, the app shows the
verdict without a percentage (it won't error).

---

## 7 · Hardening & cost

- **Secrets:** move `SECRET_KEY`, `APP_PASSWORD`, and the DB password into AWS
  Secrets Manager or SSM Parameter Store instead of the `.env` file.
- **Scale:** put the instance in an Auto Scaling group behind the same target
  group for more than one app host.
- **Private app tier:** keep EC2 in a **private** subnet; only the ALB sits in
  public subnets. Add a NAT gateway if the host needs outbound internet.
- **Cost:** the ALB, EC2, RDS, and the SageMaker **endpoint** all bill hourly.
  The endpoint is usually the largest line item — delete it when idle
  (`aws sagemaker delete-endpoint --endpoint-name titanic-endpoint`) and
  redeploy from the Model Registry when you need it again.

---

## 8 · Teardown

```bash
# app tier
aws ec2 terminate-instances --instance-ids <id>
# edge
aws elbv2 delete-load-balancer --load-balancer-arn <alb-arn>
aws elbv2 delete-target-group --target-group-arn <tg-arn>
# data tier
aws rds delete-db-instance --db-instance-identifier titanic-survival-db --skip-final-snapshot
# model (biggest cost)
aws sagemaker delete-endpoint --region us-east-1 --endpoint-name titanic-endpoint
# identity
aws iam remove-role-from-instance-profile --instance-profile-name titanic-survival-profile --role-name titanic-survival-role
aws iam delete-instance-profile --instance-profile-name titanic-survival-profile
aws iam delete-role-policy --role-name titanic-survival-role --policy-name InvokeTitanicEndpoint
aws iam delete-role --role-name titanic-survival-role
```
