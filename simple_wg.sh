#! /bin/bash

wg_iface="wg0"
cfg_file="/etc/wireguard/"$wg_iface".conf"
server_privkey="wg_privkey"
server_pubkey="wg_pubkey"
default_port=51820

RED='\033[1;31m'
NC='\033[0m'

server_conf_template="[Interface]
Address = 10.10.10.1/24
SaveConfig = true
PrivateKey = privkeyhere
ListenPort = "$default_port"
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o iface -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o iface -j MASQUERADE"

client_add="
[Peer]
PublicKey = clientpubkeyhere
AllowedIPs = clientiphere"

client_conf_template="[Interface]
Address = clientiphere
PrivateKey = clientprivkeyhere

[Peer]
PublicKey = serverpubkeyhere
Endpoint = serverip:"$default_port"
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 21
"

if [[ $1 == "init" ]]
then

    if [[ $2 == "" ]]
    then
        echo "Usage: "$0" init <interface name>"
        exit 1
    fi

    # add repo
    add-apt-repository -y ppa:wireguard/wireguard
    apt update

    # install dependencies
    apt install -y wireguard-dkms wireguard-tools linux-headers-$(uname -r) qrencode

    # create config file
    umask 077
    rm SERVER_ADDR
    [ $3 ] && echo "$3" > SERVER_ADDR
    echo "$server_conf_template" > "$cfg_file"
    sed -i "s/iface/"$2"/" "$cfg_file"

    # generate keys
    wg genkey | tee "$server_privkey" | wg pubkey > "$server_pubkey"
    content=$(cat "$server_privkey"); sed -i "s#privkeyhere#"$content"#" "$cfg_file"

    # enable forwarding
    sed -i 's/\#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sysctl -p
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # run
    chown -v root:root "$cfg_file"
    chmod -v 600 "$cfg_file"
    wg-quick up "$wg_iface"

    # enable start at boot
    systemctl enable wg-quick@"$wg_iface".service

    wg show
    echo -e "\n${RED}Make sure port "$default_port" UDP is open${NC}"
    exit 1
elif [[ $1 == "add" ]]
then
    if [[ $# != 3 ]]
    then
        echo "Usage: "$0" add <client_name> <10.10.10.x>"
        exit 1
    fi

    grep -q "$3" "$cfg_file" && echo "Client IP already exists, choose other than "$3"" && exit 1
    [[ ! -z "$(find . -name "$2".conf)" ]] && echo "Client Name already exists, choose other than "$2"" && exit 1

    # generate keys
    privkey=""$2".priv"
    pubkey=""$2".pub"
    wg genkey | tee "$privkey" | wg pubkey > "$pubkey"

    # update config file
    echo "$client_add" >> "$cfg_file"
    content=$(cat "$pubkey"); sed -i "s#clientpubkeyhere#"$content"#" "$cfg_file"
    sed -i "s/clientiphere/"$3"/" "$cfg_file"

    # generate client config
    client_conf_path=""$2".conf"
    echo "$client_conf_template" > "$client_conf_path"
    sed -i "s/clientiphere/"$3"/" "$client_conf_path"
    content=$(cat "$privkey"); sed -i "s#clientprivkeyhere#"$content"#" "$client_conf_path"
    content=$(cat "$server_pubkey"); sed -i "s#serverpubkeyhere#"$content"#" "$client_conf_path"
    server_public_ip=$(cat SERVER_ADDR 2>/dev/null || curl -s ip.me)
    sed -i "s/serverip/"$server_public_ip"/" "$client_conf_path"

    # sync wg with new config
    wg addconf "$wg_iface" <(wg-quick strip "$wg_iface")

    # show client config
    qrencode -t ansiutf8 < "$client_conf_path"
    echo -e "${RED}Config saved at $(readlink -f "$client_conf_path") ,copy to /etc/wireguard/ on client and run \"wg-quick up "$2"\" or use QR code above${NC}"
elif [[ $1 == "del" ]]
then
    if [[ $# != 2 ]]
    then
        echo "Usage: "$0" del <client_name>"
        exit 1
    fi

    # find client config
    content=$(cat "$2".pub 2>/dev/null); [[ ! $content ]] && echo ""$2" : client not found" && exit 1
    found=$(grep -m 1 -n "$content" "$cfg_file" | cut -d':' -f1); ((found -= 2)); max=$(($found + 3))
    [ ! $found ] && echo ""$2" : client public key not found in "$cfg_file"" && exit 1

    # update client config
    sed -i ""$found","$max" d" "$cfg_file"

    # remove client keys
    rm "$2".priv "$2".pub "$2".conf

    # sync wg with new config
    wg set "$wg_iface" peer "$content" remove
    wg addconf "$wg_iface" <(wg-quick strip "$wg_iface")

    echo -e "${RED}Client "$2" has been deleted${NC}"
elif [[ $1 == "qr" ]]
then
    if [[ $# != 2 ]]
    then
        echo "Usage: "$0" qr <client_name>"
        exit 1
    fi

    qrencode -t ansiutf8 < "$2".conf
else
    echo -e "Usage:\t "$0" init <interface name>
    \t "$0" add <client_name> <10.10.10.x>
    \t "$0" del <client_name>
    \t "$0" qr <client_name>"
fi
