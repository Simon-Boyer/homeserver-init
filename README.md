# homeserver-init

## Bootstrapping

```bash
cd terraform
terraform init
terraform apply -target=module.mikrotik
# boot servers
terraform apply -target=module.talos
export TF_VAR_kubeconfig=$(terraform output kubeconfig)
terraform apply
```

# Following modifications

```bash
cd terraform
terraform init
export TF_VAR_kubeconfig=$(terraform output kubeconfig)
terraform apply
```