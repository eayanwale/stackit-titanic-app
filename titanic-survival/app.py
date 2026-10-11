"""Titanic Survival — a three-tier Flask app.

Tier 1 (presentation): Jinja templates + static assets in the browser.
Tier 2 (application):   this Flask server — auth, feature engineering, and
                        the call out to the model.
Tier 3 (data/model):    a SQL user store (SQLite/RDS) for sign-in, and the
                        SageMaker endpoint that returns the prediction.

The feature engineering below mirrors the Athena CTAS that built
`titanic_clean`, so the row we send the model has exactly the columns it
was trained on, in the same order.
"""
import csv
import io
import json
import re

import boto3
from flask import (
    Flask, render_template, request, redirect, url_for, flash,
)
from flask_login import (
    LoginManager, UserMixin, login_user, logout_user,
    login_required, current_user,
)
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash

from config import Config

app = Flask(__name__)
app.config.from_object(Config)

db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.login_view = "login"


# ---------------------------------------------------------------------------
# Tier 3a — user store
# ---------------------------------------------------------------------------
class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)


@login_manager.user_loader
def load_user(user_id):
    return db.session.get(User, int(user_id))


def seed_user():
    """Create the demo sign-in account once, if the table is empty."""
    db.create_all()
    if User.query.count() == 0:
        u = User(username=app.config["APP_USERNAME"])
        u.set_password(app.config["APP_PASSWORD"])
        db.session.add(u)
        db.session.commit()


# Set-value choices used by the dropdowns in the form.
PCLASS_CHOICES = [("1", "First class"), ("2", "Second class"), ("3", "Third class")]
SEX_CHOICES = [("female", "Female"), ("male", "Male")]
EMBARKED_CHOICES = [
    ("C", "Cherbourg"), ("Q", "Queenstown"), ("S", "Southampton"),
]
TITLE_CHOICES = [
    ("Mr", "Mr"), ("Mrs", "Mrs"), ("Miss", "Miss"), ("Master", "Master"),
    ("Dr", "Dr"), ("Rev", "Rev"), ("Other", "Other"),
]


# ---------------------------------------------------------------------------
# Tier 2 — feature engineering (mirrors the titanic_clean CTAS)
# ---------------------------------------------------------------------------
# The model was trained on these columns, in this order (target `survived`
# excluded). passenger_id is an identifier the model ignores.
FEATURE_ORDER = [
    "passenger_id", "pclass", "sex", "age", "sibsp", "parch", "fare",
    "embarked", "family_size", "is_alone", "has_cabin", "title", "sex_female",
]


def build_feature_row(form):
    """Turn raw form inputs into the model's feature vector."""
    pclass = int(form["pclass"])
    sex = form["sex"]
    age = float(form["age"])
    sibsp = int(form["sibsp"])
    parch = int(form["parch"])
    fare = float(form["fare"])
    embarked = form["embarked"]
    title = form.get("title", "Mr")
    has_cabin = 1 if form.get("has_cabin") in ("1", "on", "true") else 0

    # derived, exactly as the Athena CTAS computed them
    family_size = sibsp + parch + 1
    is_alone = 1 if (sibsp + parch) == 0 else 0
    sex_female = 1 if sex == "female" else 0

    return {
        "passenger_id": 0,  # placeholder id; ignored by the model
        "pclass": pclass,
        "sex": sex,
        "age": age,
        "sibsp": sibsp,
        "parch": parch,
        "fare": fare,
        "embarked": embarked,
        "family_size": family_size,
        "is_alone": is_alone,
        "has_cabin": has_cabin,
        "title": title,
        "sex_female": sex_female,
    }


def row_to_csv(features):
    """Serialise the feature dict to a single CSV line in model order."""
    buf = io.StringIO()
    csv.writer(buf).writerow([features[c] for c in FEATURE_ORDER])
    return buf.getvalue().strip()


# ---------------------------------------------------------------------------
# Tier 3b — the model call
# ---------------------------------------------------------------------------
def parse_prediction(raw):
    """Parse whatever the endpoint returns into (label, probability).

    Autopilot endpoints return the predicted label by default, and can be
    configured to return the probability alongside it. We handle CSV
    ("1", or "1,0.87") and JSON ({"predicted_label":1,"probability":0.87}).
    """
    raw = raw.strip()
    # JSON?
    try:
        obj = json.loads(raw)
        if isinstance(obj, dict):
            label = obj.get("predicted_label", obj.get("label"))
            prob = obj.get("probability", obj.get("score"))
            return int(float(label)), (float(prob) if prob is not None else None)
        if isinstance(obj, list):
            obj = obj[0]
            return int(float(obj)), None
    except (ValueError, TypeError, KeyError):
        pass
    # CSV: "label" or "label,probability"
    parts = [p for p in re.split(r"[,\s]+", raw) if p != ""]
    if len(parts) >= 2:
        return int(float(parts[0])), float(parts[1])
    return int(float(parts[0])), None


def mock_probability(f):
    """A transparent heuristic so the app runs with no AWS setup."""
    p = 0.15
    p += 0.55 if f["sex"] == "female" else 0.0
    p += {1: 0.15, 2: 0.05, 3: -0.05}[f["pclass"]]
    if f["age"] < 12:
        p += 0.15
    if f["title"] in ("Mrs", "Miss"):
        p += 0.05
    if f["has_cabin"]:
        p += 0.08
    if f["is_alone"] and f["sex"] == "male":
        p -= 0.05
    return max(0.02, min(0.98, p))


def predict(features):
    """Return (survived: bool, probability: float|None, source: str)."""
    endpoint = app.config["SAGEMAKER_ENDPOINT_NAME"]
    if app.config["MOCK_PREDICTIONS"] or not endpoint:
        prob = mock_probability(features)
        return prob >= 0.5, prob, "mock"

    runtime = boto3.client(
        "sagemaker-runtime", region_name=app.config["AWS_REGION"]
    )
    resp = runtime.invoke_endpoint(
        EndpointName=endpoint,
        ContentType="text/csv",
        Accept="text/csv",
        Body=row_to_csv(features),
    )
    label, prob = parse_prediction(resp["Body"].read().decode("utf-8"))
    return bool(label), prob, "sagemaker"


# ---------------------------------------------------------------------------
# Tier 1/2 — routes
# ---------------------------------------------------------------------------
@app.route("/login", methods=["GET", "POST"])
def login():
    if current_user.is_authenticated:
        return redirect(url_for("index"))
    if request.method == "POST":
        user = User.query.filter_by(username=request.form.get("username")).first()
        if user and user.check_password(request.form.get("password", "")):
            login_user(user)
            return redirect(url_for("index"))
        flash("That username and password don't match. Try again.", "error")
    return render_template("login.html")


@app.route("/logout")
@login_required
def logout():
    logout_user()
    return redirect(url_for("login"))


@app.route("/")
@login_required
def index():
    return render_template(
        "index.html",
        pclass_choices=PCLASS_CHOICES,
        sex_choices=SEX_CHOICES,
        embarked_choices=EMBARKED_CHOICES,
        title_choices=TITLE_CHOICES,
    )


@app.route("/predict", methods=["POST"])
@login_required
def predict_route():
    try:
        features = build_feature_row(request.form)
    except (KeyError, ValueError):
        flash("Please fill in every field with a valid value.", "error")
        return redirect(url_for("index"))

    survived, probability, source = predict(features)
    embarked_label = dict(EMBARKED_CHOICES).get(features["embarked"], features["embarked"])
    pclass_label = dict(PCLASS_CHOICES).get(str(features["pclass"]), features["pclass"])

    return render_template(
        "result.html",
        survived=survived,
        probability=probability,
        source=source,
        name=request.form.get("name", "").strip() or "This passenger",
        features=features,
        pclass_label=pclass_label,
        embarked_label=embarked_label,
    )


@app.route("/healthz")
def healthz():
    return {"status": "ok"}, 200


with app.app_context():
    seed_user()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
