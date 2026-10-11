#!/bin/bash
set -euo pipefail

sudo dnf update -y
sudo dnf install -y python3.11

sudo mkdir -p /opt/titanic-survival
sudo cp -a /tmp/titanic-survival/. /opt/titanic-survival/
sudo find /opt/titanic-survival -name __pycache__ -type d -prune -exec rm -rf {} +
sudo rm -rf /opt/titanic-survival/.venv /opt/titanic-survival/.env /opt/titanic-survival/instance /opt/titanic-survival/terraform
sudo find /opt/titanic-survival -maxdepth 1 -name '*.db' -delete
rm -rf /tmp/titanic-survival

sudo python3.11 -m venv /opt/titanic-survival/.venv
sudo /opt/titanic-survival/.venv/bin/pip install --no-cache-dir -r /opt/titanic-survival/requirements.txt
sudo chown -R ec2-user:ec2-user /opt/titanic-survival

sudo tee /etc/systemd/system/titanic.service > /dev/null <<'EOF'
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
EOF

sudo systemctl daemon-reload
/opt/titanic-survival/.venv/bin/gunicorn --version
