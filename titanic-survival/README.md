# Titanic Survival

A three-tier Flask web app that scores a Titanic passenger against the AutoML
model trained and deployed in the STACK IT SageMaker series. Sign in, enter a
passenger's details, and the app returns a survival prediction.

- **Tier 1 — presentation:** Jinja templates + static assets (STACK IT theme).
- **Tier 2 — application:** this Flask app — auth, feature engineering, and the
  call to the model.
- **Tier 3 — data / model:** a SQL user store for sign-in, and the SageMaker
  endpoint that returns predictions.

The form collects raw inputs (class, sex, age, fare, port, family, cabin) and
the server derives the engineered features (`family_size`, `is_alone`,
`has_cabin`, `sex_female`, `title`) exactly as the `titanic_clean` Athena CTAS
did, so the row sent to the model matches its training columns.

## Run it locally (no AWS needed)

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
MOCK_PREDICTIONS=1 SECRET_KEY=dev flask run
# open http://localhost:5000  ·  sign in with  admin / titanic
```

In mock mode the app scores with a transparent heuristic, so you can click
through the whole flow with zero AWS setup.

## Point it at your SageMaker endpoint

```bash
export SECRET_KEY=$(python -c "import secrets;print(secrets.token_hex(32))")
export AWS_REGION=us-east-1
export SAGEMAKER_ENDPOINT_NAME=titanic-endpoint   # your InService endpoint
flask run
```

The host needs AWS credentials with `sagemaker:InvokeEndpoint` on that
endpoint (an EC2 instance role in production — see `DEPLOYMENT.md`).

## Deploy to AWS

Step-by-step three-tier instructions (IAM role, EC2 + gunicorn, ALB, optional
RDS) are in **`DEPLOYMENT.md`**.

## Configuration

All via environment variables (see `.env.example`): `SECRET_KEY`,
`APP_USERNAME`, `APP_PASSWORD`, `AWS_REGION`, `SAGEMAKER_ENDPOINT_NAME`,
`DATABASE_URL`, `MOCK_PREDICTIONS`.
