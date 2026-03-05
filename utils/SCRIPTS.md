terraform -chdir=envs/dev plan -var-file="projects.auto.tfvars" -var-file="terraform.tfvars"  2>&1
terraform -chdir=envs/dev apply -var-file="projects.auto.tfvars" -var-file="terraform.tfvars" -auto-approve 2>&1
terraform -chdir=envs/dev destroy -var-file="projects.auto.tfvars" -var-file="terraform.tfvars" -auto-approve 2>&1

# 1. Conectar ao cluster
aws eks update-kubeconfig --region us-east-1 --name supabase-eks

# 2. Pegar o DNS do ALB (ingress)
kubectl get ingress -n supabase-alpha
kubectl get pods -n supabase-alpha
# 3. Rollout pods (opcional)
kubectl rollout restart deployment -n supabase-alpha