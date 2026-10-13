output "container_id" {
  description = "ID of the created Docker container"
  value       = docker_container.ansible_target.id
}

output "container_name" {
  description = "Name of the created Docker container"
  value       = docker_container.ansible_target.name
}
