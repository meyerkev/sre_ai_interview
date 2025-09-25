# So this only works with existing StorageClasses
resource "kubernetes_annotations" "default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = var.default_storage_class_type
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "true"
  }

  # Only add the annotation after the EBS CSI driver is installed
  depends_on = [module.eks]
}
