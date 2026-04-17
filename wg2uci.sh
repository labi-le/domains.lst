#!/usr/bin/env bash

if [ -n "$1" ]; then
    INPUT_SOURCE="$1"
else
    INPUT_SOURCE="/dev/stdin"
fi

IFACE_NAME="${2:-awg1}" 

awk -v iface="$IFACE_NAME" '
BEGIN {
    section = ""
    listen_port = "1180"
    keepalive = "25"
}

{
    if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]*#/) next

    # Определяем текущую секцию
    if ($0 ~ /^\[.*\]$/) {
        if ($0 ~ /\[Interface\]/) section = "Interface"
        else if ($0 ~ /\[Peer\]/) section = "Peer"
        next
    }

    idx = index($0, "=")
    if (idx > 0) {
        key = substr($0, 1, idx - 1)
        val = substr($0, idx + 1)
        
        sub(/^[ \t]+/, "", key); sub(/[ \t]+$/, "", key)
        sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
        sub(/\r$/, "", val)

        key_lower = tolower(key)

        if (section == "Interface") {
            if (key_lower == "privatekey") privkey = val
            else if (key_lower == "address") address = val
            else if (key_lower == "dns") dns = val
            else if (key_lower == "mtu") mtu = val
            else if (key_lower ~ /^(jc|jmin|jmax|s[1-4]|h[1-4]|i1)$/) awg[key_lower] = val
        } else if (section == "Peer") {
            if (key_lower == "publickey") pubkey = val
            else if (key_lower == "allowedips") allowedips = val
            else if (key_lower == "endpoint") endpoint = val
        }
    }
}

END {
    print "config interface \047" iface "\047"
    print "\toption proto \047amneziawg\047"
    print "\toption private_key \047" privkey "\047"
    print "\toption listen_port \047" listen_port "\047"

    awg_keys = "jc jmin jmax s1 s2 s3 s4 h1 h2 h3 h4 i1"
    split(awg_keys, ak, " ")
    for (i=1; i<=12; i++) {
        k = ak[i]
        if (k in awg) print "\toption awg_" k " \047" awg[k] "\047"
    }

    if (mtu) print "\toption mtu \047" mtu "\047"

    split(address, addr_arr, ",")
    for (i in addr_arr) {
        a = addr_arr[i]
        sub(/^[ \t]+/, "", a); sub(/[ \t]+$/, "", a)
        if (a != "") {
            if (a !~ /\//) a = (a ~ /:/) ? a "/128" : a "/32"
            print "\tlist addresses \047" a "\047"
        }
    }

    split(dns, dns_arr, ",")
    for (i in dns_arr) {
        d = dns_arr[i]
        sub(/^[ \t]+/, "", d); sub(/[ \t]+$/, "", d)
        if (d != "") print "\tlist dns \047" d "\047"
    }
    print "\toption defaultroute \0470\047\n"

    print "config amneziawg_" iface
    print "\toption name \047" iface "_client\047"
    print "\toption public_key \047" pubkey "\047"
    print "\toption persistent_keepalive \047" keepalive "\047"

    n = split(endpoint, ep_arr, ":")
    if (n > 1) {
        port = ep_arr[n]
        host = substr(endpoint, 1, length(endpoint) - length(port) - 1)
        gsub(/\[|\]/, "", host)
        print "\toption endpoint_host \047" host "\047"
        print "\toption endpoint_port \047" port "\047"
    }

    split(allowedips, ip_arr, ",")
    for (i in ip_arr) {
        ip = ip_arr[i]
        sub(/^[ \t]+/, "", ip); sub(/[ \t]+$/, "", ip)
        if (ip != "") print "\tlist allowed_ips \047" ip "\047"
    }
}
' "$INPUT_SOURCE"
