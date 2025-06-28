#!/bin/bash

# PocketBase Docker Setup Script
# Usage: curl -fsSL https://raw.githubusercontent.com/yourusername/yourrepo/main/setup-pocketbase.sh | bash

set -e

# Configuration
PB_VERSION="0.28.3"
ROOT_DIR="/home/projects/pocketbase"
PROJECT_NAME=""
PORT=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    print_success "Docker is installed and running"
}

# Function to check if port is available
is_port_available() {
    local port=$1
    ! netstat -tuln 2>/dev/null | grep -q ":${port} " && \
    ! ss -tuln 2>/dev/null | grep -q ":${port} " && \
    ! lsof -i :${port} 2>/dev/null | grep -q "LISTEN"
}

# Function to find next available port
find_available_port() {
    local start_port=${1:-9090}
    local port=$start_port
    
    while [ $port -le 9999 ]; do
        if is_port_available $port; then
            echo $port
            return 0
        fi
        ((port++))
    done
    
    # If no port found in 9090-9999 range, try 8081-8999
    port=8081
    while [ $port -le 8999 ]; do
        if is_port_available $port; then
            echo $port
            return 0
        fi
        ((port++))
    done
    
    return 1
}

# Function to get user input
get_user_input() {
    echo ""
    print_info "Setting up PocketBase v${PB_VERSION}"
    echo ""
    
    read -p "Enter project name (e.g., contentjet-pb, sync-app): " PROJECT_NAME
    
    if [[ -z "$PROJECT_NAME" ]]; then
        print_error "Project name cannot be empty"
        exit 1
    fi
    
    echo ""
    echo "Port options:"
    echo "1) Auto-detect available port (recommended)"
    echo "2) Enter custom port number"
    echo ""
    read -p "Choose option (1 or 2): " port_option
    
    case $port_option in
        1)
            print_info "Finding available port..."
            PORT=$(find_available_port 9090)
            if [[ -z "$PORT" ]]; then
                print_error "Could not find available port. Please choose option 2."
                exit 1
            fi
            print_success "Found available port: ${PORT}"
            ;;
        2)
            read -p "Enter port number: " PORT
            if [[ -z "$PORT" ]] || ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
                print_error "Please enter a valid port number"
                exit 1
            fi
            
            if ! is_port_available $PORT; then
                print_warning "Port ${PORT} appears to be in use. Continue anyway? (y/N)"
                read -r continue_anyway
                if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                    print_info "Please choose a different port or use auto-detect option"
                    exit 1
                fi
            fi
            ;;
        *)
            print_error "Invalid option. Please choose 1 or 2."
            exit 1
            ;;
    esac
}

# Function to create project directories
create_directories() {
    local project_dir="${ROOT_DIR}/${PROJECT_NAME}"
    
    print_info "Creating project directories..."
    
    mkdir -p "${project_dir}/public"
    mkdir -p "${project_dir}/hooks"
    
    print_success "Created directories at ${project_dir}"
}

# Function to create Dockerfile
create_dockerfile() {
    local dockerfile_content='FROM alpine:latest

# Set the PocketBase version as an environment variable
ENV PB_VERSION=0.28.3

RUN apk add --no-cache \
    unzip \
    ca-certificates

# Download and unzip PocketBase
ADD https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip /tmp/pb.zip
RUN unzip /tmp/pb.zip -d /pb/

# Uncomment to copy the local pb_migrations dir into the image
# COPY ./pb_migrations /pb/pb_migrations

# Uncomment to copy the local pb_hooks dir into the image
# COPY ./pb_hooks /pb/pb_hooks

EXPOSE 8080

# Start PocketBase
CMD ["/pb/pocketbase", "serve", "--http=0.0.0.0:8080"]'
    
    echo "$dockerfile_content" > /tmp/pocketbase.dockerfile
    print_success "Created Dockerfile"
}

# Function to build Docker image
build_image() {
    print_info "Building PocketBase Docker image..."
    
    docker build -f /tmp/pocketbase.dockerfile -t pocketbase:${PB_VERSION} /tmp/
    
    print_success "Built Docker image pocketbase:${PB_VERSION}"
}

# Function to stop existing container
stop_existing_container() {
    local container_name="pocketbase-${PROJECT_NAME}"
    
    if docker ps -a --format 'table {{.Names}}' | grep -q "^${container_name}$"; then
        print_warning "Stopping existing container ${container_name}..."
        docker stop "${container_name}" 2>/dev/null || true
        docker rm "${container_name}" 2>/dev/null || true
        print_success "Removed existing container"
    fi
}

# Function to run Docker container
run_container() {
    local container_name="pocketbase-${PROJECT_NAME}"
    local project_dir="${ROOT_DIR}/${PROJECT_NAME}"
    
    print_info "Starting PocketBase container..."
    
    docker run -d \
        --name "${container_name}" \
        -p "${PORT}:8080" \
        -v "${project_dir}/public:/pb/pb_public" \
        -v "${project_dir}:/pb/pb_data" \
        -v "${project_dir}/hooks:/pb/pb_hooks" \
        pocketbase:${PB_VERSION}
    
    print_success "Started container ${container_name} on port ${PORT}"
}

# Function to show final information
show_info() {
    local container_name="pocketbase-${PROJECT_NAME}"
    local project_dir="${ROOT_DIR}/${PROJECT_NAME}"
    
    echo ""
    print_success "PocketBase setup completed!"
    echo ""
    echo "Container name: ${container_name}"
    echo "Port: ${PORT}"
    echo "Project directory: ${project_dir}"
    echo "Admin URL: http://localhost:${PORT}/_/"
    echo ""
    print_info "Useful commands:"
    echo "  View logs: docker logs ${container_name}"
    echo "  Stop container: docker stop ${container_name}"
    echo "  Start container: docker start ${container_name}"
    echo "  Remove container: docker rm ${container_name}"
    echo ""
}

# Main execution
main() {
    print_info "Starting PocketBase Docker setup..."
    
    check_docker
    get_user_input
    create_directories
    create_dockerfile
    build_image
    stop_existing_container
    run_container
    show_info
    
    # Cleanup
    rm -f /tmp/pocketbase.dockerfile
}

# Run main function
main "$@"
