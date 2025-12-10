# Deploy Grafana + Loki + Alloy no Kubernetes

Stack completo de logs para Kubernetes com deploy automatizado via Helm.

## O que é?

- **Grafana** - Interface web para visualizar logs
- **Loki** - Armazena e processa os logs
- **Alloy** - Coleta logs de todos os containers do cluster

Cada componente roda em seu próprio namespace: `grafana`, `loki` e `alloy`.

## Pré-requisitos

- Cluster Kubernetes rodando
- `kubectl` configurado
- `helm` 3.x instalado

## Deploy Rápido

```bash
# Deploy básico
./deploy-k8s.sh

# Deploy com MinIO (storage S3 local)
./deploy-k8s.sh --with-minio
```

O script faz tudo automaticamente:
- Cria os 3 namespaces
- Instala Loki, Grafana e Alloy
- Configura a comunicação entre eles

⏱️ **Tempo:** ~5-10 minutos

## Acessar o Grafana

Após o deploy:

```bash
# 1. Port-forward
kubectl port-forward -n grafana svc/my-grafana 3000:80

# 2. Obter senha
kubectl get secret -n grafana my-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
echo
```

Acesse: **http://localhost:3000**
- Usuário: `admin`
- Senha: (obtida no comando acima)

O Loki já vem configurado como datasource padrão. É só começar a usar!

## Acessar MinIO (se instalou com --with-minio)

```bash
# Port-forward
kubectl port-forward -n loki svc/my-loki-minio-console 9001:9001
```

Acesse: **http://localhost:9001**
- Usuário: `root-user`
- Senha: `supersecretpassword`

## Consultar Logs no Grafana

No Grafana, vá em **Explore** e use queries como:

```logql
# Ver todos os logs
{job="alloy"}

# Filtrar por namespace
{job="alloy", namespace="default"}

# Buscar erros
{job="alloy"} |= "error"
```

## Remover Tudo

```bash
# Remove os releases mas mantém namespaces
./undeploy-k8s.sh

# Remove tudo incluindo namespaces
./undeploy-k8s.sh --delete-namespaces
```

## Verificar Status

```bash
# Ver pods
kubectl get pods -n loki
kubectl get pods -n grafana
kubectl get pods -n alloy

# Ver logs se algo der errado
kubectl logs -n grafana deployment/my-grafana
kubectl logs -n loki -l app.kubernetes.io/name=loki
kubectl logs -n alloy daemonset/my-alloy
```

## Arquitetura

```
┌─────────────────────────────────────┐
│     Namespace: grafana              │
│   ┌─────────────────────┐           │
│   │  Grafana :3000      │───┐       │
│   └─────────────────────┘   │       │
└─────────────────────────────┼───────┘
                              │
┌─────────────────────────────┼───────┐
│     Namespace: loki         │       │
│   ┌─────────────────────┐   │       │
│   │  Loki Gateway       │◄──┘       │
│   │  + MinIO (opcional) │           │
│   └─────────────────────┘           │
└─────────────────────────────────────┘
                ▲
                │
┌───────────────┼─────────────────────┐
│     Namespace: alloy                │
│   ┌───────────┴─────────┐           │
│   │  Alloy (DaemonSet)  │           │
│   │  Coleta logs        │           │
│   └─────────────────────┘           │
└─────────────────────────────────────┘
```

## Personalizar

Edite os arquivos antes do deploy:

- `helm/values.yaml` - Configurações do Grafana
- `loki/values.yaml` - Configurações do Loki
- `alloy/values.yaml` - Configurações do Alloy

Depois rode o deploy novamente.

## Problemas Comuns

**Pods não sobem?**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Grafana não conecta no Loki?**
```bash
kubectl exec -n grafana deployment/my-grafana -- \
  curl http://my-loki-gateway.loki.svc.cluster.local/ready
```

**Alloy não envia logs?**
```bash
kubectl logs -n alloy daemonset/my-alloy
```

## Estrutura do Projeto

```
.
├── deploy-k8s.sh          # Script de deploy
├── undeploy-k8s.sh        # Script de remoção
├── helm/values.yaml       # Config Grafana
├── loki/values.yaml       # Config Loki
├── loki/values-minio.yaml # Config Loki + MinIO
└── alloy/values.yaml      # Config Alloy
```

## Recursos

- [Grafana Docs](https://grafana.com/docs/grafana/latest/)
- [Loki Docs](https://grafana.com/docs/loki/latest/)
- [Alloy Docs](https://grafana.com/docs/alloy/latest/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)

---

**Deploy simplificado para Kubernetes** 🚀
