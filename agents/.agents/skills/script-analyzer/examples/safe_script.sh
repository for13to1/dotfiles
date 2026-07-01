#!/bin/bash
# Safe script example - just lists files and shows system info

echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "Uptime: $(uptime)"

echo ""
echo "=== Current Directory Contents ==="
ls -la

echo ""
echo "=== Disk Usage ==="
df -h

echo ""
echo "=== Memory Usage ==="
free -h

echo "Done!"
