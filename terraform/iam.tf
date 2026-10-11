data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "invoke" {
  statement {
    actions   = ["sagemaker:InvokeEndpoint"]
    resources = ["arn:aws:sagemaker:${var.AWS_REGION}:${data.aws_caller_identity.current.account_id}:endpoint/${var.SAGEMAKER_ENDPOINT_NAME}"]
  }
}

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

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.APP_NAME}-profile"
  role = aws_iam_role.app.name
}
