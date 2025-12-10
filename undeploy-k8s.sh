#!/bin/bash

################################################################################
# Script de Undeploy do Stack Grafana + Loki + Alloy no Kubernetes
#
# Este script remove os deployments na seguinte ordem:
# 1. Alloy (Agente de coleta)
# 2. Grafana (Visualização)
# 3. Loki (Backend de logs)
#
# Uso: ./undeploy-k8s.sh [OPTIONS]
#
# Options:
#   --namespace     Define o namespace (padrão: observability)
#   --keep-pvcs     Mantém os PersistentVolumeClaims
#   --delete-namespace  Remove o namespace completo
#   --help          Mostra esta mensagem de ajuda
################################################################################

set -e  # Exit on error

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações padrão
NAMESPACE="observability"
KEEP_PVCS=false
DELETE_NAMESPACE=false

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
Script de Undeploy do Stack Grafana + Loki + Alloy no Kubernetes

Uso: ./undeploy-k8s.sh [OPTIONS]

Options:
  --namespace NAME       Define o namespace (padrão: observability)
  --keep-pvcs            Mantém os PersistentVolumeClaims
  --delete-namespace     Remove o namespace completo
  --help                 Mostra esta mensagem de ajuda

Exemplos:
  ./undeploy-k8s.sh                          # Remove tudo mas mantém namespace e PVCs
  ./undeploy-k8s.sh --delete-namespace       # Remove tudo incluindo namespace
  ./undeploy-k8s.sh --namespace monitoring   # Remove do namespace 'monitoring'

EOF
    exit 0
}

# Parse dos argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --keep-pvcs)
            KEEP_PVCS=true
            shift
            ;;
        --delete-namespace)
            DELETE_NAMESPACE=true
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

    # Verificar se helm está instalado
    if ! command -v helm &> /dev/null; then
        print_error "helm não encontrado. Por favor, instale o Helm 3."
        exit 1
    fi

    # Verificar se o namespace existe
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_error "Namespace '$NAMESPACE' não existe"
        exit 1
    fi

    print_success "Pré-requisitos verificados"
}

# Remover Alloy
undeploy_alloy() {
    print_header "Removendo Alloy (1/3)"

    local RELEASE_NAME="my-alloy"

    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        print_info "Desinstalando Alloy..."
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
        print_success "Alloy removido com sucesso"
    else
        print_warning "Release '$RELEASE_NAME' não encontrado no namespace '$NAMESPACE'"
    fi
}

# Remover Grafana
undeploy_grafana() {
    print_header "Removendo Grafana (2/3)"

    local RELEASE_NAME="my-grafana"

    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        print_info "Desinstalando Grafana..."
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
        print_success "Grafana removido com sucesso"
    else
        print_warning "Release '$RELEASE_NAME' não encontrado no namespace '$NAMESPACE'"
    fi
}

# Remover Loki
undeploy_loki() {
    print_header "Removendo Loki (3/3)"

    local RELEASE_NAME="my-loki"

    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        print_info "Desinstalando Loki..."
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
        print_success "Loki removido com sucesso"
    else
        print_warning "Release '$RELEASE_NAME' não encontrado no namespace '$NAMESPACE'"
    fi
}

# Remover PVCs
remove_pvcs() {
    if [ "$KEEP_PVCS" = false ]; then
        print_header "Removendo PersistentVolumeClaims"

        print_warning "Removendo PVCs do namespace '$NAMESPACE'..."
        print_warning "Isso irá DELETAR TODOS OS DADOS armazenados!"

        read -p "Tem certeza que deseja continuar? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Operação cancelada. PVCs foram mantidos."
            return
        fi

        PVC_COUNT=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

        if [ "$PVC_COUNT" -gt 0 ]; then
            print_info "Removendo $PVC_COUNT PVC(s)..."
            kubectl delete pvc --all -n "$NAMESPACE"
            print_success "PVCs removidos"
        else
            print_info "Nenhum PVC encontrado no namespace '$NAMESPACE'"
        fi
    else
        print_info "Mantendo PVCs conforme solicitado (--keep-pvcs)"
    fi
}

# Remover namespace
remove_namespace() {
    if [ "$DELETE_NAMESPACE" = true ]; then
        print_header "Removendo Namespace"

        print_warning "Removendo namespace '$NAMESPACE'..."
        print_warning "Isso irá remover TODOS OS RECURSOS do namespace!"

        read -p "Tem certeza que deseja continuar? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Operação cancelada. Namespace foi mantido."
            return
        fi

        kubectl delete namespace "$NAMESPACE"
        print_success "Namespace '$NAMESPACE' removido"
    else
        print_info "Namespace '$NAMESPACE' foi mantido"
        print_info "Para remover manualmente: kubectl delete namespace $NAMESPACE"
    fi
}

# Mostrar status final
show_final_status() {
    print_header "Status Final"

    if [ "$DELETE_NAMESPACE" = true ]; then
        print_info "Namespace '$NAMESPACE' foi completamente removido"
    else
        print_info "Recursos restantes no namespace '$NAMESPACE':"
        echo ""

        print_info "Pods:"
        kubectl get pods -n "$NAMESPACE" 2>/dev/null || print_info "  Nenhum pod encontrado"
        echo ""

        print_info "Services:"
        kubectl get svc -n "$NAMESPACE" 2>/dev/null || print_info "  Nenhum service encontrado"
        echo ""

        print_info "PersistentVolumeClaims:"
        kubectl get pvc -n "$NAMESPACE" 2>/dev/null || print_info "  Nenhum PVC encontrado"
        echo ""
    fi

    print_success "Undeploy concluído!"
}

# Função principal
main() {
    print_header "Undeploy do Stack Grafana + Loki + Alloy"

    print_info "Namespace: $NAMESPACE"
    print_info "Manter PVCs: $KEEP_PVCS"
    print_info "Deletar Namespace: $DELETE_NAMESPACE"
    echo ""

    check_prerequisites

    # Confirmar operação
    print_warning "Esta operação irá remover os seguintes releases do namespace '$NAMESPACE':"
    echo "  - my-alloy"
    echo "  - my-grafana"
    echo "  - my-loki"
    echo ""

    read -p "Deseja continuar? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Operação cancelada."
        exit 0
    fi

    # Remover na ordem inversa do deploy
    undeploy_alloy
    undeploy_grafana
    undeploy_loki

    remove_pvcs
    remove_namespace

    show_final_status
}

# Executar script
main
