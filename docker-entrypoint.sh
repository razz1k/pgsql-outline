#!/bin/bash
set -e

echo "=== PostgreSQL + VPN Container Starting ==="

# Function to parse shadowsocks URL
parse_shadowsocks_url() {
    local url="$1"
    local config="${url#ss://}"
    local method_pass="${config%@*}"
    local decoded=$(echo "$method_pass" | base64 -d 2>/dev/null || echo "$method_pass")
    local method="${decoded%:*}"
    local password="${decoded#*:}"
    local server_port="${config#*@}"
    local server="${server_port%:*}"
    local port="${server_port#*:}"
    port="${port%%\?*}"
    port="${port%%/*}"
    echo "$method|$password|$server|$port"
}

# Function to start VPN
start_vpn() {
    local config="$1"
    
    if [ -z "$config" ]; then
        echo "No VPN configuration provided"
        return 1
    fi
    
    echo "Starting VPN..."
    local parsed=$(parse_shadowsocks_url "$config")
    IFS='|' read -r method password server port <<< "$parsed"
    
    # Create shadowsocks config
    cat > /tmp/ss-config.json << EOF
{
    "server": "$server",
    "server_port": $port,
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "$password",
    "timeout": 300,
    "method": "$method"
}
EOF
    
    # Start shadowsocks
    ss-local -c /tmp/ss-config.json -f /tmp/ss.pid &
    sleep 3
    
    # Configure proxychains
    cat > /etc/proxychains4.conf << EOF
strict_chain
proxy_dns
[ProxyList]
socks5 127.0.0.1 1080
EOF
    
    echo "VPN started successfully!"
    echo "Original IP: $(curl -s --max-time 5 icanhazip.com 2>/dev/null || echo 'Unknown')"
    echo "VPN IP: $(proxychains4 curl -s --max-time 5 icanhazip.com 2>/dev/null || echo 'Failed')"
}

# Main execution
if [ -n "$VPN_CONFIG" ]; then
    start_vpn "$VPN_CONFIG"
fi

# Keep container running
if [ $# -eq 0 ]; then
    echo "Container is ready! VPN are running."
    tail -f /dev/null
else
    exec "$@"
fi
