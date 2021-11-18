resource "aws_iam_user" "s3-nextcloud" {
  name = "nextcloud-s3"
}

resource "aws_iam_access_key" "s3-access-key" {
  user = aws_iam_user.s3-nextcloud.id
}
resource "aws_s3_bucket" "bucket" {
  bucket = var.bucket_name
  acl    = "private"

  tags = {
    Name        = "nextcloud-bucket"
    Environment = "Dev"
  }
}
resource "aws_s3_bucket_public_access_block" "example" {
  bucket              = aws_s3_bucket.bucket.id
  block_public_acls   = true
  block_public_policy = true
}

resource "aws_iam_policy_attachment" "iam-attach" {
  name       = "policy attachment"
  users      = [aws_iam_user.s3-nextcloud.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}


