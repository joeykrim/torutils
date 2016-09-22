#!/bin/sh
#
#set -x

# unlock an ext4-fs encrypted directory and start the Tor daemon
#

# one time preparation before 1st run of this script:
#
# 1.  echo "0x$(head -c 16 /dev/urandom | xxd -p)" > $ldir/.cryptoSalt
# 2.  pwgen -s 32 -1 | head -n1 > $ldir/.cryptoPass
# 3.  ensure that /var/lib/tor/data is empty and owned by the tor user
# 4.  encrypt the directory /var/lib/tor/data

ldir=~/hetzner/$host  # local dir

host="mr-fox"         # Tor relay
user="tfoerste"       # remote user

if [[ ! -f $ldir/.cryptoSalt || ! -f $ldir/.cryptoPass ]]; then
  echo "salt and/or pw file not found"
  exit 1
fi

# copy the salt to the Tor relay (/tmp is a tmpfs)
# the password will never leave the local system
#
scp $ldir/.cryptoSalt $host:/tmp

# de-crypt the directory
#
cat $ldir/.cryptoPass | ssh $user@$host 'sudo -u tor e4crypt add_key -S $(cat /tmp/.cryptoSalt) /var/lib/tor/data && sudo /etc/init.d/tor start; rm /tmp/.cryptoSalt'

exit $?

