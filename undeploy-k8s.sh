#!/bin/bash

################################################################################
# Script de Undeploy do Stack Grafana + Loki + Alloy no Kubernetes
#
# Este script remove os deployments na seguinte ordem:
# 1. Alloy (namespace: alloy)
# 2. Grafana (namespace: grafana)
# 3. Loki (namespace: loki)
#
# Uso: ./undeploy-k8s.sh [OPTIONS]
#
# Options:
#   --keep-pvcs          Mantém os PersistentVolumeClaims
#   --delete-namespaces  Remove os namespaces completos
#   --help               Mostra esta mensagem de ajuda
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

KEEP_PVCS=false
DELETE_NAMESPACES=false

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

Namespaces utilizados:
  - Loki:    loki
  - Grafana: grafana
  - Alloy:   alloy

Uso: ./undeploy-k8s.sh [OPTIONS]

Options:
  --keep-pvcs          Mantém os PersistentVolumeClaims
  --delete-namespaces  Remove os namespaces completos
  --help               Mostra esta mensagem de ajuda

Exemplos:
  ./undeploy-k8s.sh                      # Remove releases mas mantém namespaces e PVCs
  ./undeploy-k8s.sh --delete-namespaces  # Remove tudo incluindo namespaces

EOF
    exit 0
}

# Parse dos argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-pvcs)
            KEEP_PVCS=true
            shift
            ;;
        --delete-namespaces)
            DELETE_NAMESPACES=true
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

    print_success "Pré-requisitos verificados"
}

# Remover Alloy
undeploy_alloy() {
    print_header "Removendo Alloy (1/3)"

    local RELEASE_NAME="my-alloy"

    if ! kubectl get namespace "$ALLOY_NAMESPACE" &> /dev/null; then
        print_warning "Namespace '$ALLOY_NAMESPACE' não existe"
        return
    fi

    if helm list -n "$ALLOY_NAMESPACE" | grep -q "$RELEASE_NAME"; then
        print_info "Desinstalando Alloy do namespace '$ALLOY_NAMESPACE'..."
        helm uninstall "$RELEASE_NAME" -n "$ALLOY_NAMESPACE"
        print_success "Alloy removido com sucesso"
    else
        print_warning "Release '$RELEASE_NAME' não encontrado no namespace '$ALLOY_NAMESPACE'"
    fi
}

# Remover Grafana
undeploy_grafana() {
    print_header "Removendo Grafana (2/3)"

    local RELEASE_NAME="my-grafana"

    if ! kubectl get namespace "$GRAFANA_NAMESPACE" &> /dev/null; then
        print_warning "Namespace '$GRAFANA_NAMESPACE' não existe"
        return
    fi

    if helm list -n "$GRAFANA_NAMESPACE" | grep -q "$RELEASE_NAME"; then
        print_info "Desinstalando Grafana do namespace '$GRAFANA_NAMESPACE'..."
        helm uninstall "$RELEASE_NAME" -n "$GRAFANA_NAMESPACE"
        print_success "Grafana removido com sucesso"
    else
        print_warning "Release '$RELEASE_NAME' não encontrado no namespace '$GRAFANA_NAMESPACE'"
    fi
}

# Remover Loki
undeploy_loki() {
    print_header "Removendo Loki (3/3)"

    local RELEASE_NAME="my-loki"

    if ! kubectl get namespace "$LOKI_NAMESPACE" &> /dev/null; then
        print_warning "Namespace '$LOKI_NAMESPACE' não existe"
        return
    fi

    if helm list -n "$LOKI_NAMESPACE" | grep -q "$RELEASE_NAME"; then
        print_info "Desinstalando Loki do namespace '$LOKI_NAMESPACE'..."
        helm uninstall "$RELEASE_NAME" -n "$LOKI_NAMESPACE"
        print_success "Loki removido com sucesso"
    else
        print_warning "Release '$RELEASE_NAME' não encontrado no namespace '$LOKI_NAMESPACE'"
    fi
}

# Remover PVCs
remove_pvcs() {
    if [ "$KEEP_PVCS" = false ]; then
        print_header "Removendo PersistentVolumeClaims"

        print_warning "Removendo PVCs dos namespaces..."
        print_warning "Isso irá DELETAR TODOS OS DADOS armazenados!"

        read -p "Tem certeza que deseja continuar? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Operação cancelada. PVCs foram mantidos."
            return
        fi

        for NS in "$LOKI_NAMESPACE" "$GRAFANA_NAMESPACE" "$ALLOY_NAMESPACE"; do
            if kubectl get namespace "$NS" &> /dev/null; then
                PVC_COUNT=$(kubectl get pvc -n "$NS" --no-headers 2>/dev/null | wc -l)

                if [ "$PVC_COUNT" -gt 0 ]; then
                    print_info "Removendo $PVC_COUNT PVC(s) do namespace '$NS'..."
                    kubectl delete pvc --all -n "$NS"
                    print_success "PVCs removidos do namespace '$NS'"
                else
                    print_info "Nenhum PVC encontrado no namespace '$NS'"
                fi
            fi
        done
    else
        print_info "Mantendo PVCs conforme solicitado (--keep-pvcs)"
    fi
}

# Remover namespaces
remove_namespaces() {
    if [ "$DELETE_NAMESPACES" = true ]; then
        print_header "Removendo Namespaces"

        print_warning "Removendo namespaces: $LOKI_NAMESPACE, $GRAFANA_NAMESPACE, $ALLOY_NAMESPACE"
        print_warning "Isso irá remover TODOS OS RECURSOS dos namespaces!"

        read -p "Tem certeza que deseja continuar? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_info "Operação cancelada. Namespaces foram mantidos."
            return
        fi

        for NS in "$LOKI_NAMESPACE" "$GRAFANA_NAMESPACE" "$ALLOY_NAMESPACE"; do
            if kubectl get namespace "$NS" &> /dev/null; then
                print_info "Removendo namespace '$NS'..."
                kubectl delete namespace "$NS"
                print_success "Namespace '$NS' removido"
            else
                print_warning "Namespace '$NS' não existe"
            fi
        done
    else
        print_info "Namespaces foram mantidos"
        print_info "Para remover manualmente:"
        echo "  kubectl delete namespace $LOKI_NAMESPACE"
        echo "  kubectl delete namespace $GRAFANA_NAMESPACE"
        echo "  kubectl delete namespace $ALLOY_NAMESPACE"
    fi
}

# Limpar recursos órfãos cluster-wide
cleanup_orphaned_cluster_resources() {
    print_header "Limpando Recursos Órfãos Cluster-Wide"

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
            print_warning "Removendo recurso órfão cluster-wide: $TYPE/$NAME"
            kubectl delete "$TYPE" "$NAME" || print_warning "Falha ao remover $TYPE/$NAME"
        fi
    done

    print_success "Limpeza de recursos órfãos concluída"
}

# Mostrar status final
show_final_status() {
    print_header "Status Final"

    if [ "$DELETE_NAMESPACES" = true ]; then
        print_info "Todos os namespaces foram removidos"
    else
        for NS in "$LOKI_NAMESPACE" "$GRAFANA_NAMESPACE" "$ALLOY_NAMESPACE"; do
            if kubectl get namespace "$NS" &> /dev/null; then
                echo ""
                print_info "=== Namespace: $NS ==="

                print_info "Pods:"
                kubectl get pods -n "$NS" 2>/dev/null || print_info "  Nenhum pod encontrado"
                echo ""

                print_info "Services:"
                kubectl get svc -n "$NS" 2>/dev/null || print_info "  Nenhum service encontrado"
                echo ""

                print_info "PersistentVolumeClaims:"
                kubectl get pvc -n "$NS" 2>/dev/null || print_info "  Nenhum PVC encontrado"
                echo ""
            fi
        done
    fi

    print_success "Undeploy concluído!"
}

# Função principal
main() {
    print_header "Undeploy do Stack Grafana + Loki + Alloy"

    print_info "Namespaces:"
    echo "  - Loki:    $LOKI_NAMESPACE"
    echo "  - Grafana: $GRAFANA_NAMESPACE"
    echo "  - Alloy:   $ALLOY_NAMESPACE"
    print_info "Manter PVCs: $KEEP_PVCS"
    print_info "Deletar Namespaces: $DELETE_NAMESPACES"
    echo ""

    check_prerequisites

    # Confirmar operação
    print_warning "Esta operação irá remover os seguintes releases:"
    echo "  - my-alloy (namespace: $ALLOY_NAMESPACE)"
    echo "  - my-grafana (namespace: $GRAFANA_NAMESPACE)"
    echo "  - my-loki (namespace: $LOKI_NAMESPACE)"
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
    cleanup_orphaned_cluster_resources
    remove_namespaces

    show_final_status
}

# Executar script
main
