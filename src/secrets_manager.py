"""
1Password CLI Secrets Manager
Provides secure access to secrets and environment variables via 1Password
"""

import os
import subprocess
import logging
from typing import Optional, Dict, Any
from dataclasses import dataclass
from pathlib import Path
import json

logger = logging.getLogger(__name__)


@dataclass
class SecretsConfig:
    """Configuration for 1Password CLI secrets management"""
    vault: str = "production"
    timeout: int = 5
    use_connect: bool = False
    connect_host: str = "localhost:8080"
    connect_token: str = ""

    @classmethod
    def from_env(cls) -> "SecretsConfig":
        """Load configuration from environment variables"""
        return cls(
            vault=os.getenv("OP_VAULT", "production"),
            timeout=int(os.getenv("OP_TIMEOUT", "5")),
            use_connect=os.getenv("OP_CONNECT_TOKEN") is not None,
            connect_host=os.getenv("OP_CONNECT_HOST", "localhost:8080"),
            connect_token=os.getenv("OP_CONNECT_TOKEN", ""),
        )

    @classmethod
    def from_file(cls, config_path: str) -> "SecretsConfig":
        """Load configuration from .env.op file"""
        config = cls()
        config_file = Path(config_path)

        if not config_file.exists():
            logger.warning(f"Config file not found: {config_path}")
            return config

        try:
            with open(config_file, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue

                    if "=" in line:
                        key, value = line.split("=", 1)
                        key = key.strip()
                        value = value.strip().strip('"').strip("'")

                        if key == "OP_VAULT":
                            config.vault = value
                        elif key == "OP_TIMEOUT":
                            config.timeout = int(value)
                        elif key == "OP_CONNECT_HOST":
                            config.connect_host = value
                        elif key == "OP_CONNECT_TOKEN":
                            config.connect_token = value
                            config.use_connect = True
        except Exception as e:
            logger.error(f"Error reading config file: {e}")

        return config


class SecretsManager:
    """Manages retrieval of secrets from 1Password"""

    def __init__(self, config: Optional[SecretsConfig] = None):
        """Initialize secrets manager with configuration"""
        self.config = config or SecretsConfig.from_env()
        self._verify_cli()
        self._cache: Dict[str, Any] = {}

    def _verify_cli(self) -> None:
        """Verify that 1Password CLI is installed and accessible"""
        try:
            result = subprocess.run(
                ["op", "--version"],
                capture_output=True,
                text=True,
                timeout=self.config.timeout,
            )
            if result.returncode != 0:
                raise RuntimeError("1Password CLI not properly installed")
            logger.info(f"1Password CLI available: {result.stdout.strip()}")
        except FileNotFoundError:
            raise RuntimeError(
                "1Password CLI (op) not found in PATH. "
                "Please install from https://developer.1password.com/docs/cli/get-started"
            )
        except subprocess.TimeoutExpired:
            raise RuntimeError("1Password CLI timed out during version check")

    def read_secret(
        self, item: str, field: str, use_cache: bool = True
    ) -> str:
        """
        Read a secret from 1Password

        Args:
            item: Item name or UUID in vault
            field: Field name to retrieve
            use_cache: Whether to cache the result

        Returns:
            The secret value

        Raises:
            ValueError: If secret cannot be retrieved
        """
        # Check cache first
        cache_key = f"{self.config.vault}/{item}/{field}"
        if use_cache and cache_key in self._cache:
            return self._cache[cache_key]

        try:
            ref = f"op://{self.config.vault}/{item}/{field}"
            result = subprocess.run(
                ["op", "read", ref],
                capture_output=True,
                text=True,
                timeout=self.config.timeout,
                env={**os.environ, "OP_CONNECT_HOST": self.config.connect_host}
                if self.config.use_connect
                else os.environ,
            )

            if result.returncode != 0:
                error_msg = result.stderr.strip()
                raise ValueError(
                    f"Failed to read {item}/{field}: {error_msg}"
                )

            value = result.stdout.strip()
            if use_cache:
                self._cache[cache_key] = value
            return value

        except subprocess.TimeoutExpired:
            raise ValueError(f"Timeout reading {item}/{field} from 1Password")
        except Exception as e:
            raise ValueError(f"Error reading {item}/{field}: {str(e)}")

    def read_reference(self, ref: str, use_cache: bool = True) -> str:
        """
        Read a secret from an explicit 1Password reference

        Args:
            ref: Full reference in format op://vault/item/field
            use_cache: Whether to cache the result

        Returns:
            The secret value
        """
        if use_cache and ref in self._cache:
            return self._cache[ref]

        try:
            result = subprocess.run(
                ["op", "read", ref],
                capture_output=True,
                text=True,
                timeout=self.config.timeout,
                env={**os.environ, "OP_CONNECT_HOST": self.config.connect_host}
                if self.config.use_connect
                else os.environ,
            )

            if result.returncode != 0:
                error_msg = result.stderr.strip()
                raise ValueError(f"Failed to read reference {ref}: {error_msg}")

            value = result.stdout.strip()
            if use_cache:
                self._cache[ref] = value
            return value

        except subprocess.TimeoutExpired:
            raise ValueError(f"Timeout reading reference {ref}")
        except Exception as e:
            raise ValueError(f"Error reading reference {ref}: {str(e)}")

    def read_json_secret(
        self, item: str, field: str = "notes", use_cache: bool = True
    ) -> Dict[str, Any]:
        """
        Read a JSON secret from 1Password

        Args:
            item: Item name or UUID in vault
            field: Field containing JSON (defaults to notes)
            use_cache: Whether to cache the result

        Returns:
            Parsed JSON dictionary

        Raises:
            ValueError: If secret cannot be retrieved or is invalid JSON
        """
        content = self.read_secret(item, field, use_cache)
        try:
            return json.loads(content)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in {item}/{field}: {str(e)}")

    def load_env_from_config(self, config_path: str = ".env.op") -> None:
        """
        Load secrets from configuration file and set as environment variables

        Args:
            config_path: Path to .env.op configuration file
        """
        config_file = Path(config_path)
        if not config_file.exists():
            logger.warning(f"Config file not found: {config_path}")
            return

        try:
            with open(config_file, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue

                    if "_REF=" in line:
                        var_name, ref = line.split("=", 1)
                        var_name = var_name.strip().replace("_REF", "")
                        ref = ref.strip().strip('"').strip("'")

                        if ref and ref.startswith("op://"):
                            try:
                                value = self.read_reference(ref)
                                os.environ[var_name] = value
                                logger.info(f"Loaded {var_name} from 1Password")
                            except ValueError as e:
                                logger.warning(f"Failed to load {var_name}: {e}")

        except Exception as e:
            logger.error(f"Error loading environment from config: {e}")

    def whoami(self) -> Dict[str, str]:
        """
        Get information about the current 1Password account

        Returns:
            Dictionary with account information
        """
        try:
            result = subprocess.run(
                ["op", "whoami"],
                capture_output=True,
                text=True,
                timeout=self.config.timeout,
            )

            if result.returncode != 0:
                raise ValueError("Failed to get account information")

            # Parse output: email, user_uuid, account_uuid, URL
            lines = result.stdout.strip().split("\n")
            info = {}
            for line in lines:
                if ":" in line:
                    key, value = line.split(":", 1)
                    info[key.strip().lower()] = value.strip()

            return info

        except Exception as e:
            logger.error(f"Error getting account info: {e}")
            return {}

    def list_items(self, vault: Optional[str] = None) -> list:
        """
        List items in a vault

        Args:
            vault: Vault name (uses configured vault if not provided)

        Returns:
            List of item information
        """
        vault = vault or self.config.vault
        try:
            result = subprocess.run(
                ["op", "item", "list", "--vault", vault],
                capture_output=True,
                text=True,
                timeout=self.config.timeout,
            )

            if result.returncode != 0:
                raise ValueError(f"Failed to list items in vault {vault}")

            return json.loads(result.stdout)

        except json.JSONDecodeError:
            logger.error("Invalid JSON from op item list")
            return []
        except Exception as e:
            logger.error(f"Error listing items: {e}")
            return []

    def clear_cache(self) -> None:
        """Clear the secrets cache"""
        self._cache.clear()
        logger.info("Secrets cache cleared")


# Global instance for convenient access
_secrets_manager: Optional[SecretsManager] = None


def get_secrets_manager(config: Optional[SecretsConfig] = None) -> SecretsManager:
    """Get or create the global secrets manager instance"""
    global _secrets_manager
    if _secrets_manager is None:
        _secrets_manager = SecretsManager(config)
    return _secrets_manager


def read_secret(item: str, field: str) -> str:
    """Convenience function to read a secret using the global manager"""
    return get_secrets_manager().read_secret(item, field)


def read_reference(ref: str) -> str:
    """Convenience function to read a secret reference using the global manager"""
    return get_secrets_manager().read_reference(ref)
