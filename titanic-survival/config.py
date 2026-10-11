"""Configuration for the Titanic Survival app.

Every value is read from an environment variable so the same code runs
locally (mock mode) and in AWS (talking to a real SageMaker endpoint).
"""
import os


class Config:
    # Flask
    SECRET_KEY = os.environ["SECRET_KEY"]

    # Tier 3 — user store (SQLite for demo; point at RDS in production)
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL", "sqlite:///titanic.db"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # Seed sign-in account (created on first run if the table is empty)
    APP_USERNAME = os.environ.get("APP_USERNAME", "admin")
    APP_PASSWORD = os.environ["APP_PASSWORD"]

    # Tier 3 — the deployed model
    AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
    SAGEMAKER_ENDPOINT_NAME = os.environ.get("SAGEMAKER_ENDPOINT_NAME", "")

    # When no endpoint is configured, or MOCK_PREDICTIONS=1, the app scores
    # locally with a heuristic so it runs with zero AWS setup.
    MOCK_PREDICTIONS = os.environ.get("MOCK_PREDICTIONS", "").lower() in (
        "1", "true", "yes",
    )
