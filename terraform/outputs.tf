output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.services : k => r.repository_url }
}

output "videos_bucket_name" {
  value = aws_s3_bucket.videos.bucket
}

output "db_endpoints" {
  value = { for k, db in aws_db_instance.services : k => db.address }
}

output "db_urls" {
  sensitive = true
  value = {
    for k, db in aws_db_instance.services :
    k => "postgres://${local.databases[k].username}:${local.databases[k].password}@${db.address}:5432/${local.databases[k].db_name}?sslmode=require"
  }
}
