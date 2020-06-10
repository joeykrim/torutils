#!/bin/sh
#
# set -x


# start or stop fuzzer(s) to achieve $1 runnning instances


set -euf
cd $(dirname $0)

if [[ $# -ne 1 ]]; then
  exit 1
fi
desired=$1

./fuzz.sh -c -a

pids=$(pgrep -f '/usr/bin/afl-fuzz -i /home/torproject/tor-fuzz-corpora/') || true

let "diff = $desired - $(echo $pids | wc -w)"

if   [[ $diff -gt 0 ]]; then
  ./fuzz.sh -u -s $diff

elif [[ $diff -lt 0 ]]; then
  victims=$(echo $pids | xargs -n 1 | shuf -n ${diff##*-})
  if [[ -n "$victims" ]]; then
    kill -15 $victims
    sleep 5
    ./fuzz.sh -c -a
  fi
fi
