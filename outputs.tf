output "output" {
  description = "Values to send Stacklet, under an `azure` key: the Storage Account name, the URL of the container holding the export, and the subscription the costs come from."
  value       = local.buckets
}
