#!/bin/bash

################################################################################
# Script de Deploy do Stack Grafana + Loki + Alloy no Kubernetes
#
# Este script faz o deploy na seguinte ordem:
# 1. Loki (namespace: loki)
# 2. Grafana (namespace: grafana)
# 3. Alloy (namespace: alloy)
#
# Uso: ./deploy-k8s.sh [OPTIONS]
#
# Options:
#   --with-minio    Usa o values-minio.yaml para o Loki (inclui MinIO)
#   --dry-run       Simula o deploy sem aplicar as mudanças
#   --help          Mostra esta mensagem de ajuda
################################################################################

set -e  # Exit on error

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações - Namespaces fixos
LOKI_NAMESPACE="loki"
GRAFANA_NAMESPACE="grafana"
ALLOY_NAMESPACE="alloy"

USE_MINIO=false
DRY_RUN=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Função para imprimir mensagens coloridas
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Função de ajuda
show_help() {
    cat << EOF
Script de Deploy do Stack Grafana + Loki + Alloy no Kubernetes

Namespaces utilizados:
  - Loki:    loki
  - Grafana: grafana
  - Alloy:   alloy

Uso: ./deploy-k8s.sh [OPTIONS]

Options:
  --with-minio      Usa o values-minio.yaml para o Loki (inclui MinIO)
  --dry-run         Simula o deploy sem aplicar as mudanças
  --help            Mostra esta mensagem de ajuda

Exemplos:
  ./deploy-k8s.sh                  # Deploy padrão
  ./deploy-k8s.sh --with-minio     # Deploy com MinIO
  ./deploy-k8s.sh --dry-run        # Simula o deploy

EOF
    exit 0
}

# Parse dos argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-minio)
            USE_MINIO=true
            shift
            ;;
        --dry-run)
            DRY_RUN="--dry-run"
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            print_error "Argumento desconhecido: $1"
            show_help
            ;;
    esac
done

# Verificar pré-requisitos
check_prerequisites() {
    print_header "Verificando Pré-requisitos"

    # Verificar se kubectl está instalado
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl não encontrado. Por favor, instale o kubectl."
        exit 1
    fi
    print_success "kubectl encontrado: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

    # Verificar se helm está instalado
    if ! command -v helm &> /dev/null; then
        print_error "helm não encontrado. Por favor, instale o Helm 3."
        exit 1
    fi
    print_success "helm encontrado: $(helm version --short)"

    # Verificar conectividade com o cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Não foi possível conectar ao cluster Kubernetes."
        exit 1
    fi
    print_success "Conectado ao cluster Kubernetes"

    # Verificar se os arquivos de values existem
    if [ ! -f "$SCRIPT_DIR/helm/values.yaml" ]; then
        print_error "Arquivo helm/values.yaml não encontrado"
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/loki/values.yaml" ]; then
        print_error "Arquivo loki/values.yaml não encontrado"
        exit 1
    fi

    if [ "$USE_MINIO" = true ] && [ ! -f "$SCRIPT_DIR/loki/values-minio.yaml" ]; then
        print_error "Arquivo loki/values-minio.yaml não encontrado"
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/alloy/values.yaml" ]; then
        print_error "Arquivo alloy/values.yaml não encontrado"
        exit 1
    fi

    print_success "Todos os arquivos de configuração encontrados"
}

# Adicionar repositórios Helm
setup_helm_repos() {
    print_header "Configurando Repositórios Helm"

    print_info "Adicionando repositório Grafana..."
    helm repo add grafana https://grafana.github.io/helm-charts || true

    print_info "Atualizando repositórios..."
    helm repo update

    print_success "Repositórios configurados"
}

# Criar namespaces
create_namespaces() {
    print_header "Criando Namespaces"

    for NS in "$LOKI_NAMESPACE" "$GRAFANA_NAMESPACE" "$ALLOY_NAMESPACE"; do
        if kubectl get namespace "$NS" &> /dev/null; then
            print_warning "Namespace '$NS' já existe"
        else
            if [ -z "$DRY_RUN" ]; then
                kubectl create namespace "$NS"
                print_success "Namespace '$NS' criado"
            else
                print_info "[DRY-RUN] Criaria o namespace '$NS'"
            fi
        fi
    done
}

# Limpar recursos órfãos
cleanup_orphaned_resources() {
    print_header "Limpando Recursos Órfãos"

    # Lista de recursos para verificar e limpar
    local RESOURCES=(
        "clusterrole:my-loki-clusterrole"
        "clusterrolebinding:my-loki-clusterrolebinding"
        "clusterrole:my-alloy"
        "clusterrolebinding:my-alloy"
    )

    for RESOURCE in "${RESOURCES[@]}"; do
        local TYPE="${RESOURCE%%:*}"
        local NAME="${RESOURCE##*:}"

        if kubectl get "$TYPE" "$NAME" &> /dev/null; then
            print_warning "Removendo recurso órfão: $TYPE/$NAME"
            if [ -z "$DRY_RUN" ]; then
                kubectl delete "$TYPE" "$NAME" || print_warning "Falha ao remover $TYPE/$NAME"
            else
                print_info "[DRY-RUN] Removeria $TYPE/$NAME"
            fi
        fi
    done

    print_success "Limpeza de recursos órfãos concluída"
}

# Deploy do Loki
deploy_loki() {
    print_header "Deploy do Loki (1/3)"

    local LOKI_VALUES="$SCRIPT_DIR/loki/values.yaml"
    local RELEASE_NAME="my-loki"

    if [ "$USE_MINIO" = true ]; then
        print_info "Usando configuração com MinIO..."
        LOKI_VALUES="$SCRIPT_DIR/loki/values-minio.yaml"
    fi

    print_info "Instalando Loki no namespace '$LOKI_NAMESPACE'..."

    if [ -z "$DRY_RUN" ]; then
        helm upgrade --install "$RELEASE_NAME" grafana/loki \
            --namespace "$LOKI_NAMESPACE" \
            --values "$LOKI_VALUES" \
            --wait \
            --timeout 10m

        print_success "Loki instalado com sucesso"

        print_info "Aguardando pods do Loki ficarem prontos..."
        kubectl wait --for=condition=ready pod \
            -l app.kubernetes.io/instance="$RELEASE_NAME" \
            -n "$LOKI_NAMESPACE" \
            --timeout=300s || print_warning "Timeout aguardando pods do Loki (pode estar normal se usar StatefulSet)"

        print_success "Loki está pronto"
    else
        helm upgrade --install "$RELEASE_NAME" grafana/loki \
            --namespace "$LOKI_NAMESPACE" \
            --values "$LOKI_VALUES" \
            --dry-run --debug
        print_info "[DRY-RUN] Loki seria instalado"
    fi
}

# Deploy do Grafana
deploy_grafana() {
    print_header "Deploy do Grafana (2/3)"

    local GRAFANA_VALUES="$SCRIPT_DIR/helm/values.yaml"
    local RELEASE_NAME="my-grafana"

    print_info "Instalando Grafana no namespace '$GRAFANA_NAMESPACE'..."

    if [ -z "$DRY_RUN" ]; then
        helm upgrade --install "$RELEASE_NAME" grafana/grafana \
            --namespace "$GRAFANA_NAMESPACE" \
            --values "$GRAFANA_VALUES" \
            --wait \
            --timeout 10m

        print_success "Grafana instalado com sucesso"

        print_info "Aguardando pods do Grafana ficarem prontos..."
        kubectl wait --for=condition=ready pod \
            -l app.kubernetes.io/name=grafana \
            -n "$GRAFANA_NAMESPACE" \
            --timeout=300s

        print_success "Grafana está pronto"
    else
        helm upgrade --install "$RELEASE_NAME" grafana/grafana \
            --namespace "$GRAFANA_NAMESPACE" \
            --values "$GRAFANA_VALUES" \
            --dry-run --debug
        print_info "[DRY-RUN] Grafana seria instalado"
    fi
}

# Deploy do Alloy
deploy_alloy() {
    print_header "Deploy do Alloy (3/3)"

    local ALLOY_VALUES="$SCRIPT_DIR/alloy/values.yaml"
    local RELEASE_NAME="my-alloy"

    print_info "Instalando Alloy no namespace '$ALLOY_NAMESPACE'..."

    if [ -z "$DRY_RUN" ]; then
        helm upgrade --install "$RELEASE_NAME" grafana/alloy \
            --namespace "$ALLOY_NAMESPACE" \
            --values "$ALLOY_VALUES" \
            --wait \
            --timeout 10m

        print_success "Alloy instalado com sucesso"

        print_info "Aguardando pods do Alloy ficarem prontos..."
        kubectl wait --for=condition=ready pod \
            -l app.kubernetes.io/name=alloy \
            -n "$ALLOY_NAMESPACE" \
            --timeout=300s || print_warning "Timeout aguardando pods do Alloy (pode estar normal se usar DaemonSet)"

        print_success "Alloy está pronto"
    else
        helm upgrade --install "$RELEASE_NAME" grafana/alloy \
            --namespace "$ALLOY_NAMESPACE" \
            --values "$ALLOY_VALUES" \
            --dry-run --debug
        print_info "[DRY-RUN] Alloy seria instalado"
    fi
}

# Mostrar informações de acesso
show_access_info() {
    print_header "Informações de Acesso"

    if [ -n "$DRY_RUN" ]; then
        print_info "[DRY-RUN] Informações de acesso não disponíveis em modo dry-run"
        return
    fi

    echo ""

    # Informações do Grafana
    print_info "=== GRAFANA (namespace: $GRAFANA_NAMESPACE) ==="
    print_info "Para acessar o Grafana, execute:"
    echo ""
    echo "  kubectl port-forward -n $GRAFANA_NAMESPACE svc/my-grafana 3000:80"
    echo ""
    print_info "Então acesse: http://localhost:3000"
    echo ""
    print_info "Credenciais do Grafana:"
    echo "  Usuário: admin"
    echo -n "  Senha: "
    kubectl get secret --namespace "$GRAFANA_NAMESPACE" my-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode || echo "N/A (verifique o secret manualmente)"
    echo ""
    echo ""

    # Informações do Loki
    print_info "=== LOKI (namespace: $LOKI_NAMESPACE) ==="
    print_info "Endpoint do Loki (interno do cluster):"
    echo "  http://my-loki-gateway.$LOKI_NAMESPACE.svc.cluster.local"
    echo ""

    if [ "$USE_MINIO" = true ]; then
        print_info "=== MINIO (Console) ==="
        print_info "Para acessar o console do MinIO:"
        echo "  kubectl port-forward -n $LOKI_NAMESPACE svc/my-loki-minio-console 9001:9001"
        echo "  Acesse: http://localhost:9001"
        echo ""
        print_info "Credenciais do MinIO:"
        echo "  Usuário: root-user"
        echo "  Senha: supersecretpassword"
        echo ""
    fi

    # Informações do Alloy
    print_info "=== ALLOY (namespace: $ALLOY_NAMESPACE) ==="
    print_info "O Alloy está coletando logs e enviando para o Loki"
    print_info "Para verificar o status dos pods do Alloy:"
    echo "  kubectl get pods -n $ALLOY_NAMESPACE -l app.kubernetes.io/name=alloy"
    echo ""

    # Status geral
    print_info "=== STATUS DOS PODS ==="
    echo ""
    echo "Loki:"
    kubectl get pods -n "$LOKI_NAMESPACE"
    echo ""
    echo "Grafana:"
    kubectl get pods -n "$GRAFANA_NAMESPACE"
    echo ""
    echo "Alloy:"
    kubectl get pods -n "$ALLOY_NAMESPACE"
    echo ""

    print_success "Deploy concluído com sucesso!"
}

# Função principal
main() {
    print_header "Deploy do Stack Grafana + Loki + Alloy"

    if [ -n "$DRY_RUN" ]; then
        print_warning "Modo DRY-RUN ativado - nenhuma mudança será aplicada"
    fi

    print_info "Namespaces:"
    echo "  - Loki:    $LOKI_NAMESPACE"
    echo "  - Grafana: $GRAFANA_NAMESPACE"
    echo "  - Alloy:   $ALLOY_NAMESPACE"
    print_info "Usar MinIO: $USE_MINIO"
    echo ""

    check_prerequisites
    setup_helm_repos
    cleanup_orphaned_resources
    create_namespaces

    # Deploy na ordem correta
    deploy_loki
    deploy_grafana
    deploy_alloy

    show_access_info
}

# Executar script
main
