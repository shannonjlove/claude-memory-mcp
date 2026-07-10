#!/bin/bash
# Tailscale + 1Password CLI Integration Setup
# This script sets up Tailscale for secure network access and 1Password CLI for secrets management

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# 1. Install Tailscale
install_tailscale() {
    log_info "Installing Tailscale..."

    if command -v tailscale &> /dev/null; then
        log_success "Tailscale already installed ($(tailscale version))"
        return 0
    fi

    case "$OSTYPE" in
        linux*)
            log_info "Detected Linux system"
            if command -v apt-get &> /dev/null; then
                curl -fsSL https://tailscale.com/install.sh | sh
            elif command -v dnf &> /dev/null; then
                dnf install tailscale
            elif command -v pacman &> /dev/null; then
                pacman -S tailscale
            else
                log_error "Unsupported package manager"
                return 1
            fi
            ;;
        darwin*)
            log_info "Detected macOS system"
            brew install tailscale
            ;;
        msys*|cygwin*|win32)
            log_info "Detected Windows system"
            log_warning "Please download and install Tailscale from https://tailscale.com/download"
            return 1
            ;;
        *)
            log_error "Unsupported OS: $OSTYPE"
            return 1
            ;;
    esac

    log_success "Tailscale installed successfully"
}

# 2. Start Tailscale daemon
start_tailscale() {
    log_info "Starting Tailscale daemon..."

    if [[ "$OSTYPE" == "linux"* ]]; then
        sudo systemctl start tailscaled
        sudo systemctl enable tailscaled
        log_success "Tailscale daemon started and enabled"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew services start tailscale
        log_success "Tailscale daemon started"
    fi
}

# 3. Authenticate with Tailscale
authenticate_tailscale() {
    log_info "Authenticating with Tailscale..."
    log_warning "You will need to open a browser to authenticate"

    if [[ "$OSTYPE" == "linux"* ]]; then
        sudo tailscale up
    else
        tailscale up
    fi

    log_success "Tailscale authentication complete"
}

# 4. Install 1Password CLI
install_1password() {
    log_info "Installing 1Password CLI..."

    if command -v op &> /dev/null; then
        log_success "1Password CLI already installed ($(op --version))"
        return 0
    fi

    case "$OSTYPE" in
        linux*)
            log_info "Installing 1Password CLI on Linux"
            # Try direct download first
            TEMP_DIR=$(mktemp -d)
            cd "$TEMP_DIR"

            # Get the latest release
            if curl -sLO "https://cache.1password.com/linux/release/amd64/op_linux_amd64_v2.zip" 2>/dev/null; then
                unzip -q op_linux_amd64_v2.zip
                sudo mv op /usr/local/bin/
                sudo chmod +x /usr/local/bin/op
                log_success "1Password CLI installed"
            else
                log_warning "Direct download failed, attempting package manager installation"
                if command -v apt-get &> /dev/null; then
                    curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
                    echo "deb [signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" | sudo tee /etc/apt/sources.list.d/1password.list > /dev/null
                    sudo apt update && sudo apt install -y 1password-cli
                    log_success "1Password CLI installed via package manager"
                else
                    log_error "Could not install 1Password CLI"
                    return 1
                fi
            fi
            cd - > /dev/null
            rm -rf "$TEMP_DIR"
            ;;
        darwin*)
            log_info "Installing 1Password CLI on macOS"
            brew install 1password-cli
            log_success "1Password CLI installed"
            ;;
        *)
            log_error "Unsupported OS for 1Password CLI: $OSTYPE"
            return 1
            ;;
    esac
}

# 5. Setup 1Password authentication
setup_1password() {
    log_info "Setting up 1Password CLI..."

    log_info "Authenticating with 1Password account..."
    op account add

    log_info "Listing available vaults..."
    op vault list

    log_success "1Password CLI configured"
}

# 6. Create environment configuration
create_env_config() {
    log_info "Creating environment configuration files..."

    local config_dir="${1:-.}"

    # Create .env.op template
    cat > "$config_dir/.env.op.example" << 'EOF'
# 1Password Integration Configuration
OP_VAULT=production
OP_CONNECT_HOST=${OP_CONNECT_HOST:-localhost:8080}
OP_TIMEOUT=5

# Secret references (use: $(op read <ref>))
# Database
DATABASE_URL_REF=op://production/Database/connection-string
DATABASE_PASSWORD_REF=op://production/Database/password
DATABASE_USER_REF=op://production/Database/username

# API Keys
GITHUB_TOKEN_REF=op://production/GitHub/token
API_KEY_REF=op://production/API/key

# Authentication
JWT_SECRET_REF=op://production/Auth/jwt-secret
SESSION_SECRET_REF=op://production/Auth/session-secret

# Tailscale Configuration
TAILSCALE_AUTH_KEY_REF=op://production/Tailscale/auth-key
TAILSCALE_API_KEY_REF=op://production/Tailscale/api-key
EOF

    # Create load-secrets.sh helper script
    cat > "$config_dir/scripts/load-secrets.sh" << 'EOF'
#!/bin/bash
# Load secrets from 1Password and set as environment variables

set -euo pipefail

# Source the configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$SCRIPT_DIR/.env.op" ]]; then
    source "$SCRIPT_DIR/.env.op"
else
    echo "Warning: .env.op not found, using defaults"
fi

# Helper function to load a secret
load_secret() {
    local var_name="$1"
    local secret_ref="$2"

    if [[ -z "$secret_ref" ]]; then
        return 0
    fi

    if ! command -v op &> /dev/null; then
        echo "Error: 1Password CLI not found" >&2
        return 1
    fi

    local value
    if value=$(op read "$secret_ref" 2>/dev/null); then
        export "$var_name=$value"
    else
        echo "Warning: Could not load $var_name from $secret_ref" >&2
        return 1
    fi
}

# Load all configured secrets
load_secret "DATABASE_URL" "${DATABASE_URL_REF:-}"
load_secret "DATABASE_PASSWORD" "${DATABASE_PASSWORD_REF:-}"
load_secret "DATABASE_USER" "${DATABASE_USER_REF:-}"
load_secret "GITHUB_TOKEN" "${GITHUB_TOKEN_REF:-}"
load_secret "API_KEY" "${API_KEY_REF:-}"
load_secret "JWT_SECRET" "${JWT_SECRET_REF:-}"
load_secret "SESSION_SECRET" "${SESSION_SECRET_REF:-}"
load_secret "TAILSCALE_AUTH_KEY" "${TAILSCALE_AUTH_KEY_REF:-}"

echo "Secrets loaded successfully"
EOF

    chmod +x "$config_dir/scripts/load-secrets.sh"

    log_success "Environment configuration created in $config_dir"
}

# 7. Test connectivity
test_connectivity() {
    log_info "Testing connectivity..."

    log_info "Tailscale status:"
    if [[ "$OSTYPE" == "linux"* ]]; then
        sudo tailscale status --self
    else
        tailscale status --self
    fi

    log_info "1Password CLI status:"
    op whoami

    log_success "All connectivity tests passed"
}

# Main execution
main() {
    log_info "Starting Tailscale + 1Password CLI setup..."

    # Run installation steps
    install_tailscale
    start_tailscale
    authenticate_tailscale

    install_1password
    setup_1password

    create_env_config "."
    test_connectivity

    log_success "Setup complete!"
    log_info "Next steps:"
    echo "  1. Copy .env.op.example to .env.op and update with your vault names"
    echo "  2. Run: source scripts/load-secrets.sh"
    echo "  3. Test with: echo \$DATABASE_URL"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
