#!/bin/bash

# usage update-blacklist.sh <configuration file>
# eg: update-blacklist.sh /etc/ipset-blacklist/ipset-blacklist.conf
#
# (date; VERBOSE=yes  time /etc/cron.daily/ip.update-blacklist ) 2>&1 |tee -a /tmp/ip.update-blacklist.log
# crontab: 
# @reboot  (sleep 300 && date; set -x; time /etc/cron.daily/ip.update-blacklist ) 2>&1 |tee  /tmp/ip.update-blacklist.log
## /usr/local/sbin/update-blacklist.sh /etc/ipset-blacklist/ipset-blacklist.conf


#  echo ${0##*/}   # script basename minus dir path


if [[ -z "$1" ]]; then
    echo "Error: please specify a configuration file, e.g. $0 /etc/ipset-blacklist/ipset-blacklist.conf"
    exit 1
fi

if ! source "$1"; then
    echo "Error: can't load configuration file $1"
    exit 1
fi

if ! which curl egrep grep ipset iptables sed sort wc &> /dev/null; then
    echo >&2 "Error: missing executables among: curl egrep grep ipset iptables sed sort wc"
    exit 1
fi

if [[ ! -d $(dirname "$IP_BLACKLIST") || ! -d $(dirname "$IP_BLACKLIST_RESTORE") ]]; then
    echo >&2 "Error: missing directory(s): $(dirname "$IP_BLACKLIST" "$IP_BLACKLIST_RESTORE"|sort -u)"
    exit 1
fi

if [ -f /etc/ip-blacklist.conf ]; then
    echo >&2 "Error: please remove /etc/ip-blacklist.conf"
    exit 1
fi

if [ -f /etc/ip-blacklist-custom.conf ]; then
    echo >&2 "Error: please reference your /etc/ip-blacklist-custom.conf as a file:// URI inside the BLACKLISTS array"
    exit 1
fi


# create the ipset if needed (or abort if does not exists and FORCE=no)
if ! ipset list -n|command grep -q "$IPSET_BLACKLIST_NAME"; then
    if [[ ${FORCE:-no} != yes ]]; then
	echo >&2 "Error: ipset does not exist yet, add it using:"
	echo >&2 "# ipset create $IPSET_BLACKLIST_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}"
	exit 1
    fi
    if ! ipset create "$IPSET_BLACKLIST_NAME" -exist hash:net family inet hashsize "${HASHSIZE:-16384}" maxelem "${MAXELEM:-65536}"; then
	echo >&2 "Error: while creating the initial ipset"
	exit 1
    fi
fi

# create the iptables binding if needed (or abort if does not exists and FORCE=no)
if ! iptables -vL INPUT|command grep -q "match-set $IPSET_BLACKLIST_NAME"; then
    # we may also have assumed that INPUT rule n°1 is about packets statistics (traffic monitoring)
    if [[ ${FORCE:-no} != yes ]]; then
	echo >&2 "Error: iptables does not have the needed ipset INPUT rule, add it using:"
	echo >&2 "# iptables -I INPUT ${IPTABLES_IPSET_RULE_NUMBER:-1} -m set --match-set $IPSET_BLACKLIST_NAME src -j DROP"
	exit 1
    fi
    if ! iptables -I INPUT "${IPTABLES_IPSET_RULE_NUMBER:-1}" -m set --match-set "$IPSET_BLACKLIST_NAME" src -j DROP; then
	echo >&2 "Error: while adding the --match-set ipset rule to iptables"
	exit 1
    fi
fi


# sleep for up to 30 seconds to not overload blocklist.de on midnight . variable PS1; it is unset in non-interactive shells,
# [ -z "$PS1" ] &&  sleep $[ ( $RANDOM % 30 )  + 1].77777s
# [[ "$-" ]] ||  date
[[ "$-" ]] ||  time sleep $[ ( $RANDOM % 9 )  + 1].77777s


    DATETIMESTR="$(date +\%Y-\%m-\%d_\%H-\%M-\%S)"
    IP_ALL="/tmp/ip.${0##*/}.ALL.txt"; echo -e "#### $0  \t$DATETIMESTR=" &> "$IP_ALL"
IP_BLACKLIST_TMP=$(mktemp  /tmp/tmp.ipv4.${0##*/}.XXXXXX.txt)
IP6_BLACKLIST_TMP=$(mktemp  /tmp/tmp.ipv6.${0##*/}.XXXXXX.txt)

for i in "${BLACKLISTS[@]}"
do
##
    IP_TMP=$(mktemp  /tmp/tmp.${0##*/}.$(basename $i).XXXXXX.txt )
#    IP_TMP="/tmp/ip.${0##*/}.txt"

    let HTTP_RC=`curl  -A "blacklist-update/script/github" --connect-timeout 10 --max-time 10 -o $IP_TMP -s -w "%{http_code}" "$i"`
    echo -e "\n### $i ,\t$(date +\%Y-\%m-\%d_\%H-\%M-\%S)"  >> "$IP_ALL"
    cat "$IP_TMP" >> "$IP_ALL"

    if (( $HTTP_RC == 200 || $HTTP_RC == 302 || $HTTP_RC == 0 )); then # "0" because file:/// returns 000
        command grep -Po '(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?' "$IP_TMP" >> "$IP_BLACKLIST_TMP"
        command grep -Po '(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))' "$IP_TMP" >> "$IP6_BLACKLIST_TMP"
#	[[ ${VERBOSE:-yes} == yes ]] && echo -n "."
	[[ ${VERBOSE:-yes} == yes ]] && echo -e "# $i : \t\n$(wc $IP_BLACKLIST_TMP $IP6_BLACKLIST_TMP)"
    else
        echo >&2 -e "\nWarning: curl returned HTTP response code $HTTP_RC for URL $i"
    fi
##    rm -f "$IP_TMP"
    at now + 11min <<<"rm -f $IP_TMP &> /dev/null"
done
	[[ ${VERBOSE:-yes} == yes ]] && echo -e "# total : \t\n$(wc $IP_ALL)"

# sort -nu does not work as expected
sed -r -e '/^(10\.|127\.|172\.16\.|192\.168\.)/d' "$IP_BLACKLIST_TMP"|sort -n|sort -mu >| "$IP_BLACKLIST"
cat "$IP6_BLACKLIST_TMP" |sort -n|sort -mu >| "$IP6_BLACKLIST"
  #grep: /tmp/ip.update-blacklist.sh.txt: No such file or directory

#rm -f "$IP_BLACKLIST_TMP"
#rm -f "$IP6_BLACKLIST_TMP"
 at now + 15min  <<<"rm -fv  $IP_BLACKLIST_TMP  $IP6_BLACKLIST_TMP > /dev/null "   


# family = inet for IPv4 only
cat >| "$IP_BLACKLIST_RESTORE" <<EOF
create $IPSET_TMP_BLACKLIST_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
create $IPSET_BLACKLIST_NAME -exist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
EOF


# can be IPv4 including netmask notation
# IPv6 ? -e "s/^([0-9a-f:./]+).*/add $IPSET_TMP_BLACKLIST_NAME \1/p" \ IPv6
sed -rn -e '/^#|^$/d' \
    -e "s/^([0-9./]+).*/add $IPSET_TMP_BLACKLIST_NAME \1/p" "$IP_BLACKLIST" >> "$IP_BLACKLIST_RESTORE"

cat >> "$IP_BLACKLIST_RESTORE" <<EOF
swap $IPSET_BLACKLIST_NAME $IPSET_TMP_BLACKLIST_NAME
destroy $IPSET_TMP_BLACKLIST_NAME
EOF

ipset -file  "$IP_BLACKLIST_RESTORE" restore

if [[ ${VERBOSE:-no} == yes ]]; then
    echo
    echo "Number of blacklisted IP/networks found: `wc -l $IP_BLACKLIST | cut -d' ' -f1`"
fi
