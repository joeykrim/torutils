#!/bin/bash
#
# set -x

# fuzz testing of Tor software as mentioned in
# https://gitweb.torproject.org/tor.git/tree/doc/HACKING/Fuzzing.md

mailto="torproject@zwiebeltoralf.de"

# 3 preparation steps at Gentoo Linux:
#
# (I)
#
# echo "sys-devel/llvm clang" >> /etc/portage/package.use/llvm
# emerge --update sys-devel/clang app-forensics/afl
#
# (II)
#
# cd ~
# git clone https://github.com/nmathewson/tor-fuzz-corpora.git
# git clone https://git.torproject.org/tor.git
# git clone https://git.torproject.org/chutney.git
#
# (III)
#
# <install recidivm>: https://jwilk.net/software/recidivm
# for i  in ./tor/src/test/fuzz/fuzz-*; do echo $(./recidivm-0.1.1/recidivm -v $i -u M 2>&1 | tail -n 1) $i ;  done | sort -n
# 46 ./tor/src/test/fuzz/fuzz-consensus
# 46 ./tor/src/test/fuzz/fuzz-descriptor
# 46 ./tor/src/test/fuzz/fuzz-diff
# 46 ./tor/src/test/fuzz/fuzz-diff-apply
# 46 ./tor/src/test/fuzz/fuzz-extrainfo
# 46 ./tor/src/test/fuzz/fuzz-hsdescv2
# 46 ./tor/src/test/fuzz/fuzz-http
# 46 ./tor/src/test/fuzz/fuzz-http-connect
# 46 ./tor/src/test/fuzz/fuzz-iptsv2
# 46 ./tor/src/test/fuzz/fuzz-microdesc
# 46 ./tor/src/test/fuzz/fuzz-vrs

function Help() {
  echo
  echo "  call: $(basename $0) [-h|-?] [-a] [-f '<fuzzer(s)>'] [-k] [-u]"
  echo
  exit 0
}


# archive all found issues
#
function archive()  {
  if [[ ! -d ~/work ]]; then
    return
  fi

  if [[ ! -d ~/archive ]]; then
    mkdir ~/archive
  fi

  ls -1d ~/work/201?????-??????_?????????_* 2>/dev/null |\
  while read d
  do
    b=$(basename $d)

    for issue in crashes hangs
    do
      if [[ -n "$(ls $d/$issue)" ]]; then
        tbz2=~/archive/${issue}_$b.tbz2
        (tar -cjvpf $tbz2 $d/$issue 2>&1; uuencode $tbz2 $(basename $tbz2)) | timeout 120 mail -s "fuzz $issue found in $b" $mailto
      fi
    done

    # catch eg.: [-] PROGRAM ABORT : Unable to communicate with fork server (OOM?)
    #
#     grep -q -F '[-]' $d/log
#     if [[ $? -eq 0 ]]; then
#       (grep -q -B 5 -A 5 -F '[-]' $d/log; uuencode $d/log $b.log) | timeout 120 mail -s "failed fuzzer: $b" $mailto
#     fi

    rm -rf $d
  done
}


# update dependencies and Tor
#
function update_tor() {
  cd $CHUTNEY_PATH
  git pull -q

  cd $TOR_FUZZ_CORPORA
  git pull -q

  cd $TOR_DIR
  before=$( git describe )
  git pull -q
  after=$( git describe )

  if [[ "$before" = "$after" ]]; then
    return 0
  fi

  make clean 2>/dev/null
  # --enable-expensive-hardening doesn't work b/c gcc hardened has USE="(-sanitize)"
  #
  ./configure
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  make -j $N fuzzers
  if [[ $? -ne 0 ]]; then
    return 1
  fi
}


# spin up fuzzers
#
function startup()  {
  cd $TOR_DIR
  cid=$( git describe | sed 's/.*\-g//g' )

  cd ~
  for f in $fuzzers
  do
    exe=$TOR_DIR/src/test/fuzz/fuzz-$f
    if [[ ! -x $exe ]]; then
      echo "fuzzer not found: $exe"
      continue
    fi

    timestamp=$( date +%Y%m%d-%H%M%S )

    odir=~/work/${timestamp}_${cid}_${f}
    mkdir -p $odir
    if [[ $? -ne 0 ]]; then
      continue
    fi

    nohup nice afl-fuzz -i ${TOR_FUZZ_CORPORA}/$f -o $odir -m 50 -- $exe &>$odir/log &
  done
}


#######################################################################
#
# main
#
if [[ $# -eq 0 ]]; then
  Help
fi

if [[ -f ~/.lock ]]; then
  kill -0 $(cat ~/.lock) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "found valid lock file ~/.lock"
    exit 1
  fi
fi
echo $$ > ~/.lock

# paths to the sources
#
export CHUTNEY_PATH=~/chutney
export TOR_DIR=~/tor
export TOR_FUZZ_CORPORA=~/tor-fuzz-corpora

# https://github.com/mirrorer/afl/blob/master/docs/env_variables.txt
#
export CFLAGS="-O2 -pipe -march=native"
export CC="afl-gcc"
export AFL_HARDEN=1
export AFL_SKIP_CPUFREQ=1
export AFL_EXIT_WHEN_DONE=1

while getopts af:hku opt
do
  case $opt in
    a)  archive
        ;;
    f)  if [[ $OPTARG =~ [[:digit:]] ]]; then
          # this works b/c there're currently 10 fuzzers defined
          #
          fuzzers=$( ls ${TOR_FUZZ_CORPORA} 2>/dev/null | sort --random-sort | head -n $OPTARG | xargs )
        else
          fuzzers="$OPTARG"
        fi
        startup
        ;;
    k)  pkill "fuzz-"
        ;;
    u)  log=$(mktemp /tmp/fuzz_XXXXXX)
        update_tor &>$log
        rc=$?
        if [[ $rc -ne 0 ]]; then
          echo rc=$rc
          ls -l $log
          exit $rc
        fi
        rm -f $log
        ;;
    *)  Help
        ;;
  esac
done

rm ~/.lock

exit 0
