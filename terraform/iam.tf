# Trust policy: lets EC2 instances assume the app role
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Invoke only the one SageMaker endpoint the app uses
data "aws_iam_policy_document" "invoke" {
  statement {
    actions   = ["sagemaker:InvokeEndpoint"]
    resources = ["arn:aws:sagemaker:${var.AWS_REGION}:${data.aws_caller_identity.current.account_id}:endpoint/${var.SAGEMAKER_ENDPOINT_NAME}"]
  }
}

# Read the app's secrets from SSM Parameter Store at boot (under SSM_PREFIX only)
data "aws_iam_policy_document" "ssm" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.AWS_REGION}:${data.aws_caller_identity.current.account_id}:parameter${var.SSM_PREFIX}/*"]
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.APP_NAME}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Only created once an endpoint name is set; until then the app runs in mock mode
resource "aws_iam_role_policy" "invoke" {
  count  = var.SAGEMAKER_ENDPOINT_NAME == "" ? 0 : 1
  name   = "InvokeTitanicEndpoint"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.invoke.json
}

resource "aws_iam_role_policy" "ssm" {
  name   = "ReadAppSecrets"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.ssm.json
}

# Session Manager access, so instances can be reached without SSH or a key pair
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile that attaches the role to the EC2 instances
resource "aws_iam_instance_profile" "app" {
  name = "${var.APP_NAME}-profile"
  role = aws_iam_role.app.name
}
