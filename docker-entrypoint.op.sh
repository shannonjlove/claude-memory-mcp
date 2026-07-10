#!/bin/bash
# Docker Entrypoint for 1Password CLI Integration
# Loads secrets from 1Password before starting the application

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[entrypoint]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if 1Password CLI is available
if ! command -v op &> /dev/null; then
    log_error "1Password CLI not found"
    exit 1
fi

log "1Password CLI version: $(op --version)"

# Wait for 1Password Connect if configured
if [[ -n "${OP_CONNECT_HOST:-}" ]]; then
    log "Waiting for 1Password Connect at $OP_CONNECT_HOST..."

    CONNECT_URL="http://${OP_CONNECT_HOST}"
    MAX_RETRIES=30
    RETRY=0

    while [[ $RETRY -lt $MAX_RETRIES ]]; do
        if curl -sf "$CONNECT_URL/health" > /dev/null 2>&1; then
            log_success "1Password Connect is ready"
            break
        fi

        RETRY=$((RETRY + 1))
        if [[ $RETRY -lt $MAX_RETRIES ]]; then
            sleep 1
        fi
    done

    if [[ $RETRY -eq $MAX_RETRIES ]]; then
        log_error "1Password Connect failed to start"
        exit 1
    fi
fi

# Authenticate with 1Password if credentials provided
if [[ -z "${OP_SESSION:-}" ]] && [[ -z "${OP_CONNECT_TOKEN:-}" ]]; then
    # Try to use existing session
    if op whoami > /dev/null 2>&1; then
        log_success "Already authenticated with 1Password"
    else
        log_warning "No 1Password authentication found"
        # Try to authenticate using service account if available
        if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
            export OP_CONNECT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN"
            log "Using service account token"
        else
            log_warning "Proceeding without 1Password authentication"
        fi
    fi
else
    log_success "1Password credentials configured"
fi

# Load environment variables from .env.op if it exists
if [[ -f ".env.op" ]]; then
    log "Loading secrets from .env.op..."

    # Source the config
    set +a
    source .env.op
    set -a

    # Load all *_REF variables from 1Password
    while IFS='=' read -r var_name var_value; do
        # Skip empty lines and comments
        [[ -z "$var_name" || "$var_name" =~ ^# ]] && continue

        # Check if this is a secret reference
        if [[ "$var_name" == *"_REF" ]]; then
            # Extract the actual variable name (remove _REF suffix)
            actual_var_name="${var_name%_REF}"

            # Clean up the value (remove quotes)
            secret_ref="${var_value%\"}"
            secret_ref="${secret_ref#\"}"
            secret_ref="${secret_ref%\'}"
            secret_ref="${secret_ref#\'}"

            # Skip if empty
            if [[ -z "$secret_ref" ]]; then
                continue
            fi

            # Load from 1Password
            if [[ "$secret_ref" == op://* ]]; then
                log "Loading $actual_var_name from 1Password..."
                if secret_value=$(op read "$secret_ref" 2>/dev/null); then
                    export "$actual_var_name=$secret_value"
                    log_success "Loaded $actual_var_name"
                else
                    log_error "Failed to load $actual_var_name"
                    # Don't exit - some secrets might be optional
                fi
            fi
        fi
    done < .env.op

    log_success "Secrets loaded from 1Password"
else
    log_warning ".env.op not found, skipping secret loading"
fi

# Verify required environment variables
REQUIRED_VARS=()

# Common required variables
if [[ -n "${REQUIRE_DATABASE:-}" ]]; then
    REQUIRED_VARS+=("DATABASE_URL")
fi

if [[ -n "${REQUIRE_API_KEY:-}" ]]; then
    REQUIRED_VARS+=("API_KEY")
fi

# Check required variables
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        log_error "Required environment variable not set: $var"
        exit 1
    fi
done

if [[ ${#REQUIRED_VARS[@]} -gt 0 ]]; then
    log_success "All required environment variables are set"
fi

# Log environment setup (without exposing secrets)
log "Environment setup complete:"
log "  OP_VAULT: ${OP_VAULT:-default}"
log "  OP_CONNECT_HOST: ${OP_CONNECT_HOST:-not set}"
log "  NODE_ENV: ${NODE_ENV:-development}"

# Start application
log "Starting application with command: $*"
exec "$@"
