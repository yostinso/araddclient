#!/bin/bash

help()
{
  echo "" >&2
  echo "client.sh -- dynamic DNS client for v4/v6 updates to Cloudflare" >&2
  echo "  -v    Verbose output"
  echo "" >&2
  echo "Usage:" >&2
  echo "  ./client.sh config.conf" >&2
  echo "" >&2
  echo "# Example config" >&2
  echo "server=api.cloudflare.com/client/v4" >&2
  echo "login=your@email.here" >&2
  echo "zone=myserver.com" >&2
  echo "hosts=\"myserver.com www.myserver.com\"" >&2
  echo "use_v6=yes" >&2
  echo "v6_if=eth0" >&2
  echo "" >&2
}

load_conf()
{
  if [ ! -f "$conf" ]; then
    echo "No config found..." >&2
    return 1
  fi

  . "$conf" && verify_conf
  return $?
}

verify_conf()
{
  for var in server login password zone hosts; do
    eval val=\$$var
    if [[ -z "$val" ]]; then
      echo "Missing configuration option: $var" >&2
      return 1
    fi
  done
  if [[ $use_v6 == "yes" ]]; then
    if [[ -z "$v6_if" ]]; then
      echo "use_v6 requires v6_if to be defined" >&2
      return 1
    fi
  fi
  return 0
}

get_ipv4()
{
  echo "xx"
}

get_ipv6()
{
  ip --oneline -6 addr show dev "$v6_if" scope global mngtmpaddr | grep -v 'inet6 f[cdef]' | awk '{ print $4 }' | head -n 1 | sed -e 's/\/.*//g'
}

call_api()
{
  local url="$1"
  local method="${2:-GET}"
  local data="$3"
  local cmd=(
    curl
    -X $method "https://$server/$url"
    -H "X-Auth-Email: $login"
    -H "Content-Type: application/json"
  )
  if [ $verbose ]; then
#    cmd+=( -v )
    cmd+=( )
  else
    cmd+=( -s )
  fi

  if [[ ! -z $data ]]; then
    cmd+=(--data "$data")
  fi
  if [ $verbose ]; then echo "${cmd[@]}" >&2; fi
  cmd+=( -H "X-Auth-Key: $password" )
  "${cmd[@]}"
}

get_zone()
{
  local zone_name="$1"
  local url="zones?name=$zone_name"
  call_api "$url" | jq -r '.result[0].id'
}

get_record()
{
  local zone_id="$1"
  local record_type="$2"
  local host_name="$3"
  local url="zones/$zone_id/dns_records?type=$record_type&name=$host_name"
  call_api "$url" | jq -r '.result[0].id'
}

set_ipv6_addr()
{
  local zone_id="$1"
  local host_name="$2"
  local addr="$3"
  local host_id=$(get_record $zone_id AAAA "$host_name")
  echo "Zone: $zone_id" >&2
  echo "Host: $host_id" >&2
  echo "Addr: $addr" >&2
  if [[ -z "$host_id" ]]; then
    echo "Couldn't find host $host_name for zone $zone_id"
    return 1
  else
    local url="zones/$zone_id/dns_records/$host_id"
    local data='{"type":"AAAA","name":"'$host_name'","content":"'$addr'"}'
    if [ $verbose ]; then echo "Updating record: $data" >&2; fi
    result=$(call_api "$url" PUT $data)
    if [[ $(echo "$result" | jq '.success') == "true" ]]; then
      echo "Updated $host_name AAAA to $addr" >&2
    else
      echo "Error updating record" >&2
      echo "$result" | jq '.errors' >&2
    fi
  fi
}

(which jq >/dev/null) || (echo "Please install 'jq'"; exit)

parse_args()
{
  while (( "$#" )); do
    case $1 in
      -v)
        echo "Enabling verbose mode..." >&2
        verbose=1
        shift
        ;;
      *)
        conf=$1
        shift
        ;;
    esac
  done
}

split_hosts()
{
  old_IFS=$IFS
  IFS=","
  read -r -a hosts <<< "$hosts"
  IFS=$old_IFS
}


parse_args "$@"

if [[ "$1" == "-v" ]]; then
  verbose=1
fi

if [[ "$conf" == "-h" || "$conf" == "--help" ]]; then
  help
  exit
elif [[ -z "$conf" ]]; then
  conf=$(dirname $0)/config.conf
fi

load_conf "$conf" || (help ; exit)

#split_hosts

zone_id=$(get_zone "$zone")
if [[ -z $zone_id ]]; then
  echo "Couldn't find zone '$zone'"
  exit
fi

ipv4=$(get_ipv4)
if [[ $use_v6 == "yes" ]]; then
  ipv6=$(get_ipv6)
  if [[ -z "$ipv6" ]]; then
    echo "Failed to get an IPv6 address" >&2
    use_ipv6="no"
  fi
fi

if [[ $use_v6 == "yes" ]]; then
  if [ $verbose ]; then echo "Setting IPv6" >&2; fi
  for host in $hosts; do
    set_ipv6_addr $zone_id $host $ipv6
  done
fi
