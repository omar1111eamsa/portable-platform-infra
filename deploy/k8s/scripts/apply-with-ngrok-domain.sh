#!/bin/bash
# Deprecated: domain is now fixed (dev.example.com, dev.example.com). Use apply-with-domain.sh.
# This script forwards to apply-with-domain.sh for backward compatibility.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/apply-with-domain.sh" "$@"
