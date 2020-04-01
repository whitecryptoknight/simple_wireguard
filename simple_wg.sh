#! /bin/bash

wg_iface="wg0"
cfg_file="/etc/wireguard/"$wg_iface".conf"
server_privkey="wg_privkey"
server_pubkey="wg_pubkey"
default_port=51820

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
AllowedIPs = clientiphere
"

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
  echo "Make sure port "$default_port" UDP is open"

  if [[ $2 == "" ]]
  then
    echo "Usage: "$0" init <interface name>"
    exit 1
  fi

  iface="$2"
  add-apt-repository -y ppa:wireguard/wireguard
  apt update
  apt install -y wireguard-dkms wireguard-tools linux-headers-$(uname -r) qrencode
  umask 077
  echo "$server_conf_template" > "$cfg_file"
  sed -i "s/iface/"$iface"/" "$cfg_file"
  wg genkey | tee "$server_privkey" | wg pubkey > "$server_pubkey"
  content=$(cat "$server_privkey"); sed -i "s#privkeyhere#"$content"#" "$cfg_file"
  sed -i 's/\#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
  sysctl -p
  echo 1 > /proc/sys/net/ipv4/ip_forward
  chown -v root:root "$cfg_file"
  chmod -v 600 "$cfg_file"
  wg-quick up "$wg_iface"
  systemctl enable wg-quick@"$wg_iface".service
  wg show
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

  privkey=""$2".priv"
  pubkey=""$2".pub"

  wg genkey | tee "$privkey" | wg pubkey > "$pubkey"
  echo "$client_add" >> "$cfg_file"
  content=$(cat "$pubkey"); sed -i "s#clientpubkeyhere#"$content"#" "$cfg_file"
  sed -i "s/clientiphere/"$3"/" "$cfg_file"

  client_conf_path=""$2".conf"
  echo "$client_conf_template" > "$client_conf_path"
  sed -i "s/clientiphere/"$3"/" "$client_conf_path"
  content=$(cat "$privkey"); sed -i "s#clientprivkeyhere#"$content"#" "$client_conf_path"
  content=$(cat "$server_pubkey"); sed -i "s#serverpubkeyhere#"$content"#" "$client_conf_path"
  server_public_ip=$(curl -s ip.me || echo "server_public_ip")
  sed -i "s/serverip/"$server_public_ip"/" "$client_conf_path"
  wg addconf "$wg_iface" <(wg-quick strip "$wg_iface")

  echo "Config saved at $(readlink -f "$client_conf_path") ,copy to /etc/wireguard/ on client and run \"wg-quick up "$2"\" or use QR code below"
  qrencode -t ansiutf8 < "$client_conf_path"
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
  \t "$0" qr <client_name>"
fi
