# Supabase Self-Hosted — Infraestrutura Terraform

Terraform para rodar o **Supabase** no AWS com:

- **EKS** — executa todos os microsserviços do Supabase
- **Aurora Serverless v2 (PostgreSQL 15)** — banco de dados compartilhado, sem pod de Postgres no Kubernetes
- **ALB (Application Load Balancer)** — exposto publicamente via HTTP
- **Multi-tenant por banco de dados** — cada projeto recebe seu próprio banco dentro do mesmo cluster Aurora, compartilhando os serviços no EKS

```
Internet
    │
    ▼
AWS ALB (HTTP)
    │  (roteado por hostname por projeto)
    ▼
EKS Cluster
├── Namespace: supabase-project-alpha
│   ├── Kong (API Gateway)
│   ├── PostgREST, GoTrue, Realtime, Storage, Meta, Studio
│   └── → Aurora DB: project_alpha
│
└── Namespace: supabase-project-beta
    └── → Aurora DB: project_beta

Aurora Serverless v2 (compartilhado)
├── project_alpha
└── project_beta
```

---

## Pré-requisitos

| Ferramenta | Versão mínima | Para que serve |
|---|---|---|
| Terraform | >= 1.5 | Gerenciar a infraestrutura |
| AWS CLI | qualquer | Credenciais, Secrets Manager, reboot do Aurora |
| `psql` | qualquer | Executar o script de init do banco (`aurora-db-init`) |
| `kubectl` | qualquer | Validar pods após o deploy |
| `helm` | >= 3 | Instalado automaticamente pelo Terraform (opcional para debug) |

### Permissões AWS necessárias

A conta/role usada para o `terraform apply` precisa de:

```
IAM, EKS, EC2 (VPC/SG/subnets), RDS (Aurora), S3, SecretsManager
```

### Acesso de rede à Aurora

O `aurora-db-init` roda um script `psql` **localmente** na sua máquina. Para isso funcionar, a Aurora precisa estar acessível:

- Em desenvolvimento (`envs/dev`): a Aurora é criada com `publicly_accessible = true` — basta ter internet.
- Em produção: use VPN, bastion host ou AWS Cloud9 dentro da VPC.

---

## Estrutura dos Módulos

```
terraform/
├── versions.tf          # Providers e versões
├── variables.tf         # Variáveis do módulo raiz
├── main.tf              # Composição dos módulos (uso avançado)
├── outputs.tf           # Outputs do módulo raiz
│
├── modules/
│   ├── vpc/             # VPC, subnets públicas/privadas, NAT GW, endpoint S3
│   ├── eks/             # Cluster EKS, node group, IRSA, addons (LBC, EBS CSI)
│   ├── aurora/          # Cluster Aurora Serverless v2 + parameter group + reboot
│   ├── aurora-db-init/  # Init do banco por projeto (roles, extensões, schemas, publicação)
│   └── supabase-project/# helm_release por projeto + bucket S3 + IRSA para Storage
│
└── envs/
    └── dev/             # <<< USAR ESTE para terraform init/apply
        ├── main.tf
        ├── terraform.tfvars      # Configurações não-secretas
        └── projects.auto.tfvars  # Segredos por projeto (gitignored)
```

> Sempre execute o Terraform a partir de `terraform/envs/dev/`.

---

## Passo a Passo

### 1. Preencher os segredos

Edite o arquivo `terraform/envs/dev/projects.auto.tfvars`:

```hcl
projects = [
  {
    name = "meu-projeto"

    # JWT — assina tokens da API pública
    jwt_secret = "..."   # string aleatória >= 32 chars
    anon_key   = "..."   # JWT com role=anon assinado pelo jwt_secret
    service_key = "..."  # JWT com role=service_role assinado pelo jwt_secret

    # Senhas dos roles PostgreSQL (strings aleatórias >= 16 chars)
    authenticator_password = "..."
    auth_password          = "..."
    storage_password       = "..."
    realtime_password      = "..."
    admin_password         = "..."
    studio_password        = "..."

    # Chaves do Realtime
    realtime_enc_key         = "..."  # hex >= 32 chars
    realtime_secret_key_base = "..."  # string >= 64 chars
  }
]
```

#### Como gerar cada valor

**`jwt_secret`** — string aleatória >= 32 chars:
```bash
openssl rand -hex 32
```

**`anon_key`** e **`service_key`** — JWTs assinados com o `jwt_secret`.
Use o snippet Node.js abaixo ou o site [jwt.io](https://jwt.io):

```js
// npm install jsonwebtoken  (ou: node -e "...")
const jwt = require('jsonwebtoken')
const secret = 'SEU_JWT_SECRET_AQUI'

const anonKey = jwt.sign(
  { role: 'anon', iss: 'supabase', iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000) + 10*365*24*3600 },
  secret
)
const serviceKey = jwt.sign(
  { role: 'service_role', iss: 'supabase', iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000) + 10*365*24*3600 },
  secret
)
console.log('anon_key:   ', anonKey)
console.log('service_key:', serviceKey)
```

**Senhas dos roles** — qualquer string aleatória >= 16 chars:
```bash
openssl rand -base64 16
```

**`realtime_enc_key`** — hex de 32+ bytes:
```bash
openssl rand -hex 32
```

**`realtime_secret_key_base`** — string de 64+ chars:
```bash
openssl rand -hex 64
```

> **Importante:** Nunca commite `projects.auto.tfvars` com valores reais.
> Em CI/CD, passe os segredos via variável de ambiente:
> ```bash
> export TF_VAR_projects='[{"name":"meu-projeto","jwt_secret":"..."}]'
> ```

---

### 2. Configurar região e cluster (opcional)

Edite `terraform/envs/dev/terraform.tfvars` se quiser mudar os padrões:

```hcl
aws_region            = "us-east-1"   # região AWS
cluster_name          = "supabase-eks"
aurora_engine_version = "15.4"
aurora_min_capacity   = 0.5           # ACUs mínimos (custo mínimo em idle)
aurora_max_capacity   = 8             # ACUs máximos
eks_node_instance_type = "t3.medium"
eks_node_desired_size  = 2
```

---

### 3. Executar o Terraform

```bash
cd terraform/envs/dev

# Baixar providers e módulos
terraform init

# Visualizar o que será criado (sem aplicar)
terraform plan

# Criar a infraestrutura
terraform apply
```

O `apply` executa na seguinte ordem automática:

1. **VPC** — rede base
2. **EKS** — cluster e nodes
3. **Aurora** — cluster + parameter group → **reboot automático** (ativa replicação lógica)
4. **aurora-db-init** — por projeto: cria banco, roles, extensões, schemas, publicação
5. **supabase-project** — por projeto: S3, IRSA, Helm release no EKS

> O reboot do Aurora após a criação é automático e necessário para ativar
> `rds.logical_replication = 1` (obrigatório para o serviço Realtime).
> O Terraform aguarda o cluster ficar disponível antes de continuar.

---

## Conectar ao Aurora pelo psql (do seu PC)

Em `envs/dev`, a Aurora é criada com acesso público (`publicly_accessible = true`).

```bash
# 1. Pegar o endpoint
AURORA_HOST=$(terraform -chdir=terraform/envs/dev output -raw aurora_cluster_endpoint)

# 2. Pegar o ARN do secret da senha master
SECRET_ARN=$(terraform -chdir=terraform/envs/dev output -raw aurora_master_secret_arn)

# 3. Buscar a senha no Secrets Manager
PGPASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query "SecretString" \
  --output text | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

# 4. Conectar
psql -h "$AURORA_HOST" -U supabase_master -d postgres
```

> Para restringir o acesso ao seu IP específico (mais seguro), edite `allowed_cidr_blocks` em
> `terraform/envs/dev/main.tf`:
> ```hcl
> allowed_cidr_blocks = ["SEU_IP_AQUI/32"]  # ex: ["177.100.200.50/32"]
> ```
> Descubra seu IP com: `curl ifconfig.me`

---

## Validação Pós-Deploy

```bash
# Pods rodando no EKS
kubectl get pods -A

# Saúde do Kong (pegar DNS do ALB no AWS Console ou via kubectl get ingress -A)
curl http://<ALB-DNS>/health

# PostgREST respondendo
curl http://<ALB-DNS>/rest/v1/ -H "apikey: <anon_key>"

# Criar usuário de teste
curl -X POST http://<ALB-DNS>/auth/v1/signup \
  -H "apikey: <anon_key>" \
  -H "Content-Type: application/json" \
  -d '{"email":"teste@exemplo.com","password":"senha1234"}'

# Checar replication slots (conectado ao banco do projeto)
psql ... -c "SELECT slot_name, active FROM pg_replication_slots;"

# Listar extensões instaladas
psql ... -c "SELECT extname FROM pg_extension;"
```

---

## Adicionar um Novo Projeto

Adicione um segundo objeto no array `projects` em `projects.auto.tfvars`:

```hcl
projects = [
  {
    name = "projeto-alpha"
    # ... campos do primeiro projeto
  },
  {
    name = "projeto-beta"
    jwt_secret               = "..."
    anon_key                 = "..."
    service_key              = "..."
    authenticator_password   = "..."
    auth_password            = "..."
    storage_password         = "..."
    realtime_password        = "..."
    admin_password           = "..."
    studio_password          = "..."
    realtime_enc_key         = "..."
    realtime_secret_key_base = "..."
  }
]
```

Depois rode `terraform apply`. O Terraform cria apenas os recursos novos (banco, namespace, Helm release) sem recriar o que já existe.

---

## Limitações do Aurora (sem suporte)

As extensões abaixo **não estão disponíveis** no Aurora PostgreSQL e por isso estão desabilitadas:

| Extensão | Impacto | Alternativa |
|---|---|---|
| `pg_graphql` | API GraphQL (`/graphql/v1`) não funciona | Usar REST em `/rest/v1/` |
| `pg_net` | Banco não pode fazer chamadas HTTP | Usar K8s CronJobs ou Lambda |
| `pgjwt` | Verificação JWT dentro do banco indisponível | GoTrue (Auth) cuida disso externamente |
| `pgsodium` / `supabase_vault` | Vault indisponível | Usar AWS Secrets Manager |

---

## Segurança

- `projects.auto.tfvars` está no `.gitignore` — nunca commite com segredos reais
- O `publicly_accessible = true` é **apenas para dev** — remova em produção
- O password master do Aurora fica no **AWS Secrets Manager** (gerenciado automaticamente pelo RDS)
- Storage API acessa o S3 via **IRSA** (IAM Role for Service Accounts) — sem chaves estáticas
