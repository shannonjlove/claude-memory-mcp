"""
Tailscale Configuration for Claude Memory MCP Server

This module provides Tailscale network configuration for secure remote access
to the Claude Memory MCP server through the Tailscale mesh network.
"""

import os
from dataclasses import dataclass
from typing import Optional


@dataclass
class TailscaleConfig:
    """Tailscale configuration for Claude Memory MCP"""

    enabled: bool = os.getenv('TAILSCALE_ENABLED', '').lower() == 'true'
    hostname: str = os.getenv('TAILSCALE_HOSTNAME', 'claude-memory-mcp')
    bind_address: str = os.getenv('BIND_ADDRESS', 'localhost')
    bind_port: int = int(os.getenv('BIND_PORT', '3000'))
    auth_key: Optional[str] = os.getenv('TAILSCALE_AUTH_KEY')

    # Security settings
    trust_proxy: bool = enabled
    require_https: bool = False

    # Health check
    health_check_enabled: bool = True
    health_check_path: str = '/health'

    def to_dict(self) -> dict:
        """Convert configuration to dictionary"""
        return {
            'enabled': self.enabled,
            'hostname': self.hostname,
            'bind_address': self.bind_address,
            'bind_port': self.bind_port,
            'security': {
                'trust_proxy': self.trust_proxy,
                'require_https': self.require_https,
            },
            'health_check': {
                'enabled': self.health_check_enabled,
                'path': self.health_check_path,
            },
        }

    def get_server_config(self) -> dict:
        """Get server configuration for Tailscale integration"""
        return {
            'host': self.bind_address,
            'port': self.bind_port,
            'timeout': 60,
        }

    def __post_init__(self):
        """Validate configuration"""
        if self.bind_port < 1 or self.bind_port > 65535:
            raise ValueError(f"Invalid port number: {self.bind_port}")

        if self.enabled:
            import logging
            logger = logging.getLogger(__name__)
            logger.info(f"Tailscale enabled: {self.hostname}")
            logger.info(f"Bind address: {self.bind_address}:{self.bind_port}")
