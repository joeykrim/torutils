#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# count inbound to local ORPort per remote ip address

function show() {
  local sum=0
  local ips=0

  while read -r conns ip
  do
    if [[ $conns -gt $limit ]]; then
      printf "%-10s %-40s %5i\n" address$v $ip $conns
      (( ++ips ))
      (( sum = sum + conns ))
    fi
  done < <(
    ss --no-header --tcp -${v:-4} --numeric |
    grep "^ESTAB .* $(sed -e 's,\[,\\[,g' -e 's,\],\\],g' <<< $relay) " |
    awk '{ print $5 }' | sort | sed 's,:[[:digit:]]*$,,g' | uniq -c
  )

  if [[ $ips -gt 0 ]]; then
    printf "relay:%-40s  adresses:%-5i  conns:%-5i\n\n" $relay $ips $sum
  fi
}


#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

limit=2

# is the local relay address contained in the ORPort config value ?
relays=$(grep "^ORPort" /etc/tor/torrc{,2} 2>/dev/null | awk '{ print $2 }' | sort)
if [[ ! $relays =~ '.' ]]; then
  # no, so get it here
  address=$(grep "^Address" /etc/tor/torrc | awk '{ print $2 }' | sort -u)
  relays="$address:$relays"
fi

while getopts l:r: opt
do
  case $opt in
    l)  limit=$OPTARG ;;
    r)  relays=$OPTARG ;;
    *)  echo "unknown parameter '$opt'"; exit 1 ;;
  esac
done

for v in '' 6
do
  for relay in $relays
  do
    if [[ $relay =~ '.' && "$v" = "" ]]; then
      show
    elif [[ ! $relay =~ '.' && "$v" = "6" ]]; then
      show
    fi
  done
done
