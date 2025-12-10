# Deploy do Stack Grafana + Loki + Alloy no Kubernetes

Este guia descreve como fazer o deploy do stack completo de observabilidade (Grafana + Loki + Alloy) em um cluster Kubernetes usando Helm.

## Índice

- [Pré-requisitos](#pré-requisitos)
- [Componentes](#componentes)
- [Estrutura de Arquivos](#estrutura-de-arquivos)
- [Uso Rápido](#uso-rápido)
- [Deploy](#deploy)
- [Undeploy](#undeploy)
- [Personalização](#personalização)
- [Troubleshooting](#troubleshooting)

## Pré-requisitos

Antes de executar o script de deploy, certifique-se de ter:

1. **kubectl** instalado e configurado para acessar seu cluster Kubernetes
   ```bash
   kubectl version --client
   kubectl cluster-info
   ```

2. **Helm 3** instalado
   ```bash
   helm version
   ```

3. Acesso ao cluster Kubernetes com permissões para criar namespaces e resources

4. (Opcional) Storage class configurado no cluster para PersistentVolumes

## Componentes

O stack é composto por três componentes principais:

### 1. Loki
- **Função**: Backend de armazenamento e processamento de logs
- **Ordem de Deploy**: 1º (precisa estar pronto antes dos outros)
- **Configuração**: `loki/values.yaml` ou `loki/values-minio.yaml`
- **Porta**: 3100 (interno)

### 2. Grafana
- **Função**: Interface de visualização e análise de logs
- **Ordem de Deploy**: 2º
- **Configuração**: `helm/values.yaml`
- **Porta**: 3000 (via port-forward ou service)
- **Credenciais padrão**: admin / (senha gerada automaticamente)

### 3. Alloy
- **Função**: Agente de coleta de logs (substituto do Promtail/Agent)
- **Ordem de Deploy**: 3º (último)
- **Configuração**: `alloy/values.yaml`
- **Tipo**: DaemonSet (roda em todos os nodes)

## Estrutura de Arquivos

```
grafana/
├── deploy-k8s.sh           # Script de deploy
├── undeploy-k8s.sh         # Script de remoção
├── README-DEPLOY.md        # Este arquivo
├── helm/
│   └── values.yaml         # Configuração do Grafana
├── loki/
│   ├── values.yaml         # Configuração básica do Loki
│   └── values-minio.yaml   # Configuração do Loki com MinIO (S3)
└── alloy/
    └── values.yaml         # Configuração do Alloy
```

## Uso Rápido

### Deploy Padrão

```bash
# Deploy com configuração básica
./deploy-k8s.sh
```

### Deploy com MinIO

```bash
# Deploy incluindo MinIO como backend S3 para o Loki
./deploy-k8s.sh --with-minio
```

### Deploy em Namespace Customizado

```bash
# Deploy no namespace 'monitoring'
./deploy-k8s.sh --namespace monitoring
```

### Dry Run (Testar sem aplicar)

```bash
# Simula o deploy sem fazer mudanças no cluster
./deploy-k8s.sh --dry-run
```

## Deploy

### Opções do Script de Deploy

```bash
./deploy-k8s.sh [OPTIONS]

Options:
  --with-minio      Usa o values-minio.yaml para o Loki (inclui MinIO)
  --namespace NAME  Define o namespace (padrão: observability)
  --dry-run         Simula o deploy sem aplicar as mudanças
  --help            Mostra a mensagem de ajuda
```

### Exemplos

```bash
# 1. Deploy básico no namespace padrão (observability)
./deploy-k8s.sh

# 2. Deploy com MinIO no namespace monitoring
./deploy-k8s.sh --with-minio --namespace monitoring

# 3. Testar o deploy antes de aplicar
./deploy-k8s.sh --dry-run

# 4. Deploy com MinIO e teste antes
./deploy-k8s.sh --with-minio --dry-run
```

### O que o Script Faz

1. ✅ Verifica se kubectl e helm estão instalados
2. ✅ Adiciona o repositório Helm da Grafana
3. ✅ Cria o namespace especificado
4. ✅ Faz deploy do Loki (com ou sem MinIO)
5. ✅ Aguarda o Loki estar pronto
6. ✅ Faz deploy do Grafana
7. ✅ Aguarda o Grafana estar pronto
8. ✅ Faz deploy do Alloy
9. ✅ Mostra informações de acesso

### Tempo Estimado

- Deploy completo: ~5-10 minutos
- Depende da capacidade do cluster e velocidade de download das imagens

## Acessando os Serviços

### Grafana

Após o deploy, para acessar o Grafana:

```bash
# 1. Port-forward para localhost
kubectl port-forward -n observability svc/my-grafana 3000:80

# 2. Acesse no navegador
# http://localhost:3000

# 3. Obter a senha do admin
kubectl get secret -n observability my-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
echo
```

**Credenciais:**
- Usuário: `admin`
- Senha: (obtida com o comando acima)

### Loki

O Loki está acessível internamente no cluster:

```bash
# Endpoint interno
http://my-loki-gateway.observability.svc.cluster.local
```

### MinIO (se usando --with-minio)

```bash
# 1. Port-forward para localhost
kubectl port-forward -n observability svc/my-loki-minio-console 9001:9001

# 2. Acesse no navegador
# http://localhost:9001
```

**Credenciais do MinIO:**
- Usuário: `root-user`
- Senha: `supersecretpassword`

### Alloy

O Alloy roda como DaemonSet e coleta logs automaticamente:

```bash
# Verificar status dos pods do Alloy
kubectl get pods -n observability -l app.kubernetes.io/name=alloy

# Ver logs do Alloy
kubectl logs -n observability -l app.kubernetes.io/name=alloy --tail=50
```

## Undeploy

### Opções do Script de Undeploy

```bash
./undeploy-k8s.sh [OPTIONS]

Options:
  --namespace NAME       Define o namespace (padrão: observability)
  --keep-pvcs            Mantém os PersistentVolumeClaims
  --delete-namespace     Remove o namespace completo
  --help                 Mostra a mensagem de ajuda
```

### Exemplos de Undeploy

```bash
# 1. Remover releases mas manter namespace e PVCs
./undeploy-k8s.sh

# 2. Remover tudo incluindo namespace (mas mantém PVCs)
./undeploy-k8s.sh --delete-namespace

# 3. Remover tudo mas manter os PVCs
./undeploy-k8s.sh --keep-pvcs

# 4. Remover de namespace específico
./undeploy-k8s.sh --namespace monitoring

# 5. Remoção completa (namespace + PVCs + releases)
./undeploy-k8s.sh --delete-namespace
# Depois confirme a remoção dos PVCs quando perguntado
```

### O que o Script de Undeploy Faz

1. ✅ Remove o Alloy (na ordem inversa do deploy)
2. ✅ Remove o Grafana
3. ✅ Remove o Loki
4. ✅ (Opcional) Remove os PVCs
5. ✅ (Opcional) Remove o namespace

## Personalização

### Modificar Configurações do Grafana

Edite o arquivo `helm/values.yaml`:

```yaml
# Exemplo: Alterar plugins
plugins:
  - grafana-piechart-panel
  - grafana-clock-panel

# Exemplo: Configurar datasource do Loki
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      url: http://my-loki-gateway.loki.svc.cluster.local/
```

### Modificar Configurações do Loki

Edite o arquivo `loki/values.yaml` ou `loki/values-minio.yaml`:

```yaml
# Exemplo: Ajustar retenção de dados
loki:
  limits_config:
    retention_period: 744h  # 31 dias
```

### Modificar Configurações do Alloy

Edite o arquivo `alloy/values.yaml`:

```yaml
# Exemplo: Alterar o endpoint do Loki
alloy:
  configMap:
    content: |
      loki.write "default" {
        endpoint {
          url = "http://meu-loki.namespace.svc.cluster.local/loki/api/v1/push"
        }
      }
```

## Troubleshooting

### Pods não iniciam

```bash
# Verificar status dos pods
kubectl get pods -n observability

# Ver detalhes de um pod específico
kubectl describe pod <pod-name> -n observability

# Ver logs de um pod
kubectl logs <pod-name> -n observability
```

### Problemas com PVCs

```bash
# Verificar PVCs
kubectl get pvc -n observability

# Ver detalhes de um PVC
kubectl describe pvc <pvc-name> -n observability

# Verificar StorageClass disponível
kubectl get storageclass
```

### Loki não recebe logs

```bash
# 1. Verificar se o Alloy está rodando
kubectl get pods -n observability -l app.kubernetes.io/name=alloy

# 2. Verificar logs do Alloy
kubectl logs -n observability -l app.kubernetes.io/name=alloy --tail=100

# 3. Verificar se o Loki está acessível
kubectl exec -it -n observability deployment/my-grafana -- \
  curl -s http://my-loki-gateway.observability.svc.cluster.local/ready
```

### Grafana não consegue conectar ao Loki

```bash
# 1. Verificar se o datasource está configurado corretamente
kubectl exec -it -n observability deployment/my-grafana -- \
  cat /etc/grafana/provisioning/datasources/datasources.yaml

# 2. Testar conectividade do Grafana para o Loki
kubectl exec -it -n observability deployment/my-grafana -- \
  curl -s http://my-loki-gateway.observability.svc.cluster.local/ready
```

### Helm release falhou

```bash
# Listar releases com problemas
helm list -n observability --failed

# Ver histórico de um release
helm history my-loki -n observability

# Rollback se necessário
helm rollback my-loki -n observability
```

### Verificar recursos do cluster

```bash
# Ver uso de recursos
kubectl top nodes
kubectl top pods -n observability

# Ver eventos do namespace
kubectl get events -n observability --sort-by='.lastTimestamp'
```

## Arquitetura do Deploy

```
┌─────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                  │
│                                                       │
│  ┌─────────────────────────────────────────────┐    │
│  │         Namespace: observability              │    │
│  │                                                │    │
│  │  ┌──────────────┐      ┌──────────────┐      │    │
│  │  │   Grafana    │─────→│     Loki     │      │    │
│  │  │ (Deployment) │      │ (StatefulSet)│      │    │
│  │  │              │      │              │      │    │
│  │  │  Port: 3000  │      │  Port: 3100  │      │    │
│  │  └──────────────┘      └──────┬───────┘      │    │
│  │                               │               │    │
│  │                               │               │    │
│  │                        ┌──────▼────────┐      │    │
│  │                        │    MinIO      │      │    │
│  │                        │  (Optional)   │      │    │
│  │                        │   S3 Backend  │      │    │
│  │                        └───────────────┘      │    │
│  │                                                │    │
│  │  ┌──────────────────────────────────────┐    │    │
│  │  │          Alloy (DaemonSet)           │    │    │
│  │  │  (Runs on all nodes, collects logs) │────┘    │
│  │  └──────────────────────────────────────┘         │
│  └─────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────┘
```

## Recursos Adicionais

- [Documentação do Grafana](https://grafana.com/docs/grafana/latest/)
- [Documentação do Loki](https://grafana.com/docs/loki/latest/)
- [Documentação do Alloy](https://grafana.com/docs/alloy/latest/)
- [Helm Charts da Grafana](https://github.com/grafana/helm-charts)

## Suporte

Para problemas ou dúvidas:
1. Consulte a seção [Troubleshooting](#troubleshooting)
2. Verifique os logs dos pods
3. Consulte a documentação oficial dos componentes

---

**Nota**: Este é um ambiente de observabilidade completo. Para produção, considere:
- Configurar autenticação adequada
- Ajustar recursos (CPU/Memory) conforme necessário
- Configurar backup dos dados
- Implementar alta disponibilidade (múltiplas réplicas)
- Configurar ingress para acesso externo seguro
