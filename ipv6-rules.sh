#!/bin/bash
# set -x


function addCommon() {
  ip6tables -t raw -P PREROUTING ACCEPT     # drop explicitely
  ip6tables        -P INPUT      DROP       # accept explicitely
  ip6tables        -P OUTPUT     ACCEPT     # accept all

  # allow loopback
  ip6tables -A INPUT --in-interface lo                                -j ACCEPT -m comment --comment "$(date -R)"
  ip6tables -A INPUT -p udp --source fe80::/10 --dst ff02::1  -j ACCEPT
  
  # make sure NEW incoming tcp connections are SYN packets
  ip6tables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
  
  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  ip6tables -A INPUT -p tcp --dport ${port:-22} -j ACCEPT
 
  ## ratelimit ICMP echo
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 6/s -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP
  ip6tables -A INPUT -p ipv6-icmp                            -j ACCEPT
}


function __fill_lists() {
  # dig +short snowflake-01.torproject.net. AAAA
  # curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o - | jq -cr '.relays[].a | select(length > 1) | .[1]' | tr -d ']['
  echo 2a0c:dd40:1:b::42 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2001:858:2:2:aabb:0:563b:1526 2607:8500:154::3 2610:1c0:0:5::131 2620:13:4000:6000::1000:118 |
  xargs -r -n 1 -P 20 ipset add -exist $trustlist

  curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - |
  jq -cr '.relays[].a' | tr '][",' ' ' | sort | uniq -c | grep -v ' 1 ' |
  xargs -r -n 1 | grep -F ':' |
  xargs -r -n 1 -P 20 ipset add -exist $multilist
}


function addTor() {
  local blocklist=tor-ddos6
  local multilist=tor-multi6
  local trustlist=tor-trust6

  ipset create -exist $blocklist hash:ip family inet6 timeout 1800
  ipset create -exist $multilist hash:ip family inet6
  ipset create -exist $trustlist hash:ip family inet6

  __fill_lists & # lazy fill to minimize restart time

  for relay in $relays
  do
    read -r orip orport <<< $(sed -e 's,]:, ,' <<< $relay | tr '[' ' ')

    # block SYN flood
    ip6tables -t raw -A PREROUTING -p tcp --dst $orip --dport $orport --syn -m hashlimit --hashlimit-name $blocklist --hashlimit-mode srcip --hashlimit-srcmask 128 --hashlimit-above 6/minute --hashlimit-burst 6 --hashlimit-htable-expire 60000 -j SET --add-set $blocklist src --exist
    ip6tables -t raw -A PREROUTING -p tcp -m set --match-set $blocklist src -j DROP

    # trust Tor people
    ip6tables -A INPUT -p tcp --dst $orip --dport $orport -m set --match-set $trustlist src -j ACCEPT

    # block too much connections
    ip6tables -A INPUT -p tcp --dst $orip --dport $orport -m connlimit --connlimit-mask 128 --connlimit-above 3 -j SET --add-set $blocklist src --exist
    ip6tables -A INPUT -p tcp -m set --match-set $blocklist src -j DROP
  
    # ignore connection attempts
    ip6tables -A INPUT -p tcp --dst $orip --dport $orport --syn -m connlimit --connlimit-mask 128 --connlimit-above 1 -m set ! --match-set $multilist src -j DROP
    ip6tables -A INPUT -p tcp --dst $orip --dport $orport --syn -m connlimit --connlimit-mask 128 --connlimit-above 2 -j DROP
  
    # allow remaining
    ip6tables -A INPUT -p tcp --dst $orip --dport $orport -j ACCEPT
  done

  # allow already established connections
  ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  ip6tables -A INPUT -m conntrack --ctstate INVALID             -j DROP
}


# only useful for Hetzner customers: https://wiki.hetzner.de/index.php/System_Monitor_(SysMon)
function addHetzner() {
  local monlist=hetzner-monlist6

  ipset create -exist $monlist hash:ip family inet6

  # getent ahostsv6 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u | xargs
  for i in 2a01:4f8:0:a101::5:1 2a01:4f8:0:a101::6:1 2a01:4f8:0:a101::6:2 2a01:4f8:0:a101::6:3 2a01:4f8:0:a112::c:1
  do
    ipset add -exist $monlist $i
  done
  ip6tables -A INPUT -m set --match-set $monlist src -j ACCEPT
}


function clearAll() {
  ip6tables -P INPUT   ACCEPT

  for table in filter raw
  do
    ip6tables -F -t $table
    ip6tables -X -t $table
    ip6tables -Z -t $table
  done
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor, this should match ORPort, see https://github.com/toralf/torutils/issues/1
relays="[2a01:4f9:3b:468e::13]:9001 [2a01:4f9:3b:468e::13]:443"

case $1 in
  start)  addCommon
          addTor
          addHetzner
          ;;
  stop)   clearAll
          ;;
  *)      ip6tables -nv -L -t raw || echo -e "\n\n+ + + Warning: you kernel lacks CONFIG_IP6_NF_RAW=y\n\n"
          echo
          ip6tables -nv -L
          ;;
esac

