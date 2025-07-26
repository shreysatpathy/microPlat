#!/bin/bash

# ML Platform Port Forward Script
# Manages port forwarding for all ML platform services

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Debug mode
DEBUG=${DEBUG:-false}

# Default namespaces
MONITORING_NS=${MONITORING_NS:-monitoring}
ARGOCD_NS=${ARGOCD_NS:-argocd}
JUPYTERHUB_NS=${JUPYTERHUB_NS:-ml-dev}
RAY_NS=${RAY_NS:-ml-dev}

# Port mappings
GRAFANA_PORT=${GRAFANA_PORT:-3000}
ARGOCD_PORT=${ARGOCD_PORT:-8080}
JUPYTERHUB_PORT=${JUPYTERHUB_PORT:-6767}
RAY_DASHBOARD_PORT=${RAY_DASHBOARD_PORT:-8265}
PROMETHEUS_PORT=${PROMETHEUS_PORT:-9090}
ALERTMANAGER_PORT=${ALERTMANAGER_PORT:-9093}

# PID file for tracking port forwards
PID_FILE="/tmp/ml-platform-port-forwards.pids"

# Print functions
print_header() {
    echo -e "${BLUE}[ML-PLATFORM]${NC} $1"
}

print_status() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${GREEN}[DEBUG]${NC} $1"
    fi
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a service exists
check_service() {
    local service_name=$1
    local namespace=$2
    
    if kubectl get service "$service_name" -n "$namespace" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to start port forwarding
start_port_forward() {
    local service_name=$1
    local namespace=$2
    local local_port=$3
    local service_port=$4
    local display_name=$5
    
    print_status "Starting port forward: $display_name ($service_name:$service_port -> localhost:$local_port)"
    
    # Kill any existing port forward on this port
    pkill -f "kubectl.*port-forward.*:$local_port" 2>/dev/null || true
    
    # Start new port forward in background
    kubectl port-forward -n "$namespace" "svc/$service_name" "$local_port:$service_port" >/dev/null 2>&1 &
    local pid=$!
    
    # Store PID
    echo "$pid:$display_name:$local_port" >> "$PID_FILE"
    
    # Give it a moment to start
    sleep 1
    
    # Check if it's still running
    if kill -0 "$pid" 2>/dev/null; then
        print_info "$display_name available at: http://localhost:$local_port"
        return 0
    else
        print_error "Failed to start port forward for $display_name"
        return 1
    fi
}

# Function to stop all port forwards
stop_port_forwards() {
    print_header "Stopping all port forwards..."
    
    if [[ -f "$PID_FILE" ]]; then
        while IFS=':' read -r pid name port; do
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                print_status "Stopping $name (PID: $pid, Port: $port)"
                kill "$pid" 2>/dev/null || true
            fi
        done < "$PID_FILE"
        rm -f "$PID_FILE"
    fi
    
    # Also kill any kubectl port-forward processes
    pkill -f "kubectl.*port-forward" 2>/dev/null || true
    
    print_info "All port forwards stopped"
}

# Function to show status
show_status() {
    print_header "Port Forward Status"
    echo ""
    
    if [[ ! -f "$PID_FILE" ]]; then
        print_warning "No active port forwards found"
        return
    fi
    
    local active_count=0
    while IFS=':' read -r pid name port; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            print_info "$name: http://localhost:$port (PID: $pid) "
            ((active_count++))
        else
            print_warning "$name: Not running "
        fi
    done < "$PID_FILE"
    
    echo ""
    if [[ $active_count -gt 0 ]]; then
        print_info "$active_count port forward(s) active"
    else
        print_warning "No active port forwards"
    fi
}

# Function to start all port forwards
start_all() {
    print_header "Starting ML Platform Port Forwards"
    echo ""
    
    # Clean up any existing port forwards
    stop_port_forwards
    
    # Initialize PID file
    > "$PID_FILE"
    
    # Start Grafana
    if check_service "kube-prometheus-stack-grafana" "$MONITORING_NS"; then
        start_port_forward "kube-prometheus-stack-grafana" "$MONITORING_NS" "$GRAFANA_PORT" "80" "Grafana"
    else
        print_warning "Grafana service not found in namespace $MONITORING_NS"
    fi
    
    # Start Prometheus
    if check_service "kube-prometheus-stack-prometheus" "$MONITORING_NS"; then
        start_port_forward "kube-prometheus-stack-prometheus" "$MONITORING_NS" "$PROMETHEUS_PORT" "9090" "Prometheus"
    else
        print_warning "Prometheus service not found in namespace $MONITORING_NS"
    fi
    
    # Start Alertmanager
    if check_service "kube-prometheus-stack-alertmanager" "$MONITORING_NS"; then
        start_port_forward "kube-prometheus-stack-alertmanager" "$MONITORING_NS" "$ALERTMANAGER_PORT" "9093" "Alertmanager"
    else
        print_warning "Alertmanager service not found in namespace $MONITORING_NS"
    fi
    
    # Start ArgoCD
    if check_service "argocd-server" "$ARGOCD_NS"; then
        start_port_forward "argocd-server" "$ARGOCD_NS" "$ARGOCD_PORT" "80" "ArgoCD"
    else
        print_warning "ArgoCD service not found in namespace $ARGOCD_NS"
    fi
    
    # Start JupyterHub (service name is 'hub')
    if check_service "proxy-public" "$JUPYTERHUB_NS"; then
        start_port_forward "proxy-public" "$JUPYTERHUB_NS" "$JUPYTERHUB_PORT" "80" "JupyterHub"
    else
        print_warning "JupyterHub service 'proxy-public' not found in namespace $JUPYTERHUB_NS"
    fi
    
    # Start Ray Dashboard
    if check_service "ray-sample-cluster-head-svc" "$RAY_NS"; then
        start_port_forward "ray-sample-cluster-head-svc" "$RAY_NS" "$RAY_DASHBOARD_PORT" "8265" "Ray Dashboard"
    else
        print_warning "Ray Dashboard service 'ray-sample-cluster-head-svc' not found in namespace $RAY_NS"
    fi
    
    echo ""
    print_header "Port Forward Setup Complete!"
    echo ""
    show_status
    echo ""
    print_info "To stop all port forwards, run: $0 stop"
    print_info "To check status, run: $0 status"
    echo ""
    print_warning "Keep this terminal open to maintain port forwards"
    print_warning "Press Ctrl+C to stop all port forwards"
    
    # Wait for interrupt
    trap stop_port_forwards EXIT INT TERM
    
    # Keep script running and monitor port forwards
    while true; do
        sleep 10
        # Check if any port forwards died and restart them
        if [[ -f "$PID_FILE" ]]; then
            while IFS=':' read -r pid name port; do
                if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
                    print_warning "$name port forward died, restarting..."
                    # Remove dead entry
                    grep -v "^$pid:" "$PID_FILE" > "${PID_FILE}.tmp" && mv "${PID_FILE}.tmp" "$PID_FILE"
                    # Restart based on service name
                    case "$name" in
                        "Grafana")
                            start_port_forward "kube-prometheus-stack-grafana" "$MONITORING_NS" "$GRAFANA_PORT" "80" "Grafana"
                            ;;
                        "Prometheus")
                            start_port_forward "kube-prometheus-stack-prometheus" "$MONITORING_NS" "$PROMETHEUS_PORT" "9090" "Prometheus"
                            ;;
                        "Alertmanager")
                            start_port_forward "kube-prometheus-stack-alertmanager" "$MONITORING_NS" "$ALERTMANAGER_PORT" "9093" "Alertmanager"
                            ;;
                        "ArgoCD")
                            start_port_forward "argocd-server" "$ARGOCD_NS" "$ARGOCD_PORT" "80" "ArgoCD"
                            ;;
                        "JupyterHub")
                            start_port_forward "proxy-public" "$JUPYTERHUB_NS" "$JUPYTERHUB_PORT" "80" "JupyterHub"
                            ;;
                        "Ray Dashboard")
                            start_port_forward "ray-sample-cluster-head-svc" "$RAY_NS" "$RAY_DASHBOARD_PORT" "8265" "Ray Dashboard"
                            ;;
                    esac
                fi
            done < "$PID_FILE"
        fi
    done
}

# Show usage
show_usage() {
    echo "ML Platform Port Forward Manager"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start     - Start all port forwards (default)"
    echo "  stop      - Stop all port forwards"
    echo "  status    - Show status of port forwards"
    echo "  restart   - Restart all port forwards"
    echo "  debug     - Run in debug mode with verbose output"
    echo "  help      - Show this help message"
    echo ""
    echo "Services and Ports:"
    echo "  Grafana:        http://localhost:$GRAFANA_PORT"
    echo "  Prometheus:     http://localhost:$PROMETHEUS_PORT"
    echo "  Alertmanager:   http://localhost:$ALERTMANAGER_PORT"
    echo "  ArgoCD:         http://localhost:$ARGOCD_PORT"
    echo "  JupyterHub:     http://localhost:$JUPYTERHUB_PORT"
    echo "  Ray Dashboard:  http://localhost:$RAY_DASHBOARD_PORT"
    echo ""
    echo "Environment Variables:"
    echo "  MONITORING_NS     - Monitoring namespace (default: monitoring)"
    echo "  ARGOCD_NS         - ArgoCD namespace (default: argocd)"
    echo "  JUPYTERHUB_NS     - JupyterHub namespace (default: ml-dev)"
    echo "  RAY_NS            - Ray namespace (default: ml-dev)"
    echo "  GRAFANA_PORT      - Grafana local port (default: 3000)"
    echo "  ARGOCD_PORT       - ArgoCD local port (default: 8080)"
    echo "  JUPYTERHUB_PORT   - JupyterHub local port (default: 6767)"
    echo "  RAY_DASHBOARD_PORT - Ray Dashboard local port (default: 8265)"
    echo "  DEBUG             - Enable debug output (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0 start"
    echo "  $0 debug"
    echo "  DEBUG=true $0 start"
    echo "  JUPYTERHUB_NS=default $0 start"
}

# Main script logic
case "${1:-start}" in
    start|up)
        start_all
        ;;
    stop|down)
        stop_port_forwards
        ;;
    status)
        show_status
        ;;
    restart)
        stop_port_forwards
        sleep 2
        start_all
        ;;
    debug)
        DEBUG=true
        print_info "Debug mode enabled"
        start_all
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
