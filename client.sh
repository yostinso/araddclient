#!/bin/bash

help()
{
  echo "" >&2
  echo "client.sh -- dynamic DNS client for v4/v6 updates to Cloudflare" >&2
  echo "" >&2
  echo "Usage:" >&2
  echo "  ./client.sh [-v] [-v] [-v] [-f] config.conf" >&2
  echo ""
  echo "        Uses config.conf in the script's folder by default."
  echo "  -v    Verbose output. Level 3 includes API debugging and therefore passwords." >&2
  echo "  -f    Force update regardless of age or matching IP" >&2
  echo "" >&2
  echo "# Example config" >&2
  echo "server=api.cloudflare.com/client/v4" >&2
  echo "login=your@email.here" >&2
  echo "zone=myserver.com" >&2
  echo "hosts=\"myserver.com www.myserver.com\"" >&2
  echo "use_v4=yes              # Attempt to update A records. Default yes." >&2
  echo "v4_method=icanhazip     # Use icanhazip for public IPv4 address. Default icanhazip." >&2
  echo "                        # You can also specify 'meraki' or a custom function, see below." >&2
  echo "use_v6=no               # Attempt to update AAAA records. Default no." >&2
  echo "v6_method=ifaddr        # Use the local interface non-private IP (recommended)." >&2
  echo "                        # You can also specify 'icanhazip' or a custom function, see below." >&2
  echo "v6_if=eth0              # Required if v6_method=ifaddr; which interface to inspect?" >&2
  echo "update_frequency=300    # How frequently to send an IP update (when changed); default is 300 seconds." >&2
  echo "" >&2
  echo "# For custom sources of IPv4, define a function:" >&2
  echo "v4_method=mymethod" >&2
  echo "# The config is just a bash script; define a method that returns an" >&2
  echo "# ip as the only result." >&2
  echo "mymethod()" >&2
  echo "{" >&2
  echo "  curl -s http://10.0.0.1/index.json | jq -r '.connection_state.wired_uplinks[0].ip'" >&2
  echo "}" >&2
  echo "" >&2
}

load_conf()
{
  local conf="$1"
  if [[ -z "$conf" ]]; then
    conf="$(dirname $0)/config.conf"
  fi
  if [ ! -f "$conf" ]; then
    echo "No config found..." >&2
    return 1
  fi

  . "$conf"
  if [[ $? -ne 0 ]]; then return $?; fi
  update_frequency=${update_frequency:-300}
  use_v4=${use_v4:-yes}
  v4_method=${v4_method:-icanhazip}
  v6_method=${v6_method:-ifaddr}
  verify_conf
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
  case $v4_method in
    icanhazip|meraki)
      ;;
    *)
      if [[ $(type -t "$v4_method") != "function" ]]; then
        echo "Invalid v4_method: $v4_method" >&2
        return 1
      fi
      ;;
  esac
  case $v6_method in
    ifaddr|icanhazip)
      ;;
    *)
      if [[ $(type -t "$v6_method") != "function" ]]; then
        echo "Invalid v6_method: $v4_method" >&2
        return 1
      fi
      ;;
  esac
  return 0
}

icanhazip()
{
  local protocol_ver="$1"
  result=$(curl -s -$protocol_ver 'https://icanhazip.com/')
  if [[ $verbose && $protocol_ver == 6 ]]; then
    if_result=$(ifaddr)
    if [[ $if_result != $result ]]; then
      echo "  Warning: icanhazip and ifaddr disagree: $result != $if_result" >&2
      echo "  Warning: You are probably sending your temporary/private IPv6 address. Consider using v6_method=ifaddr." >&2
    fi
  fi
  echo $result
}

meraki()
{
  gw=$(dig +short mx.meraki.com)
  if [[ -z "$gw" ]]; then
    gw=$(ip --oneline -4 route list default | awk '{ print $3 }')
  fi
  if [[ ! -z $gw ]]; then
    if [ $verbose -gt 1 ]; then echo "  Using Meraki gateway $gw" >&2; fi
    curl -s 'http://192.168.2.1/index.json' | jq -r '.connection_state.wired_uplinks[0].ip'
  else
    echo "Couldn't get IP from Meraki gateway." >&2
    echo ""
  fi
}

ifaddr() {
  ip --oneline -6 addr show dev "$v6_if" scope global mngtmpaddr | grep -v 'inet6 f[cdef]' | awk '{ print $4 }' | head -n 1 | sed -e 's/\/.*//g'
}

get_ipv4()
{
  if [ $verbose ]; then echo "Using IPv4 discovery method $v4_method... " >&2; fi
  local result=$($v4_method 4)
  if [ $verbose ]; then echo "  Found $result" >&2; echo "" >&2; fi
  echo $result
}

get_ipv6()
{
  if [ $verbose ]; then echo "Using IPv6 discovery method $v6_method... " >&2; fi
  local result=$($v6_method 6)
  if [ $verbose ]; then echo "  Found $result" >&2; echo "" >&2; fi
  echo $result
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

  case $verbose in
    2)
      cmd+=()
      ;;
    3)
      cmd+=( -v )
      ;;
    *)
      cmd+=( -s )
      ;;
  esac

  if [[ ! -z $data ]]; then
    cmd+=(--data "$data")
  fi
  if [ $verbose ]; then echo "  ${cmd[@]}" >&2; fi
  cmd+=( -H "X-Auth-Key: $password" )
  "${cmd[@]}"
}

get_zone()
{
  local zone_name="$1"
  local url="zones?name=$zone_name"
  if [ $verbose ]; then echo "Getting the Cloudflare zone ID..." >&2; fi
  result=$(call_api "$url" | jq -r '.result[0].id')
  if [ $verbose ]; then echo "  Found $result" >&2; echo "" >&2; fi
  echo $result
}

get_record()
{
  local zone_id="$1"
  local record_type="$2"
  local host_name="$3"
  local url="zones/$zone_id/dns_records?type=$record_type&name=$host_name"
  call_api "$url" | jq -r '.result[0].id'
}

touch_host()
{
  local host_name="$1"
  local record_type="$2"
  local addr="$3"
  echo "$addr" > last_update/${host_name}_${record_type}.last
}

should_update()
{
  local host_name="$1"
  local record_type="$2"
  local addr="$3"
  local filename="last_update/${host_name}_${record_type}.last"
  local touched_at=0
  local last_addr=""
  if [[ -f "$filename" ]]; then
    touched_at=$(stat -c "%Y" "$filename")
    last_addr=$(cat "$filename")
  fi
  local now=$(date '+%s')
  local age=$(($now - $touched_at))
  if [ $verbose ]; then echo "  $host_name $record_type is $age seconds old" >&2; fi
  if [[ "$force_update" ]]; then
    echo "  Forcing update for $host_name $record_type" >&2
    return 0
  elif [[ "$age" -gt "$update_frequency" ]]; then
    if [[ "$last_addr" == "$addr" ]]; then
      echo "  Skipping update for $host_name $record_type: Address hasn't changed." >&2
      return 1
    else
      return 0
    fi
  else
    echo "  Skipping update for $host_name $record_type: Too recently updated." >&2
    return 1
  fi
}

update_record()
{
  local zone_id="$1"
  local host_name="$2"
  local addr="$3"
  local record_type="$4"

  should_update "$host_name" $record_type "$addr"
  if [[ $? -ne 0 ]]; then
    return
  fi

  local host_id=$(get_record $zone_id $record_type "$host_name")
  echo "    Zone: $zone_id" >&2
  echo "    Host: $host_id" >&2
  echo "    Addr: $addr" >&2
  if [[ -z "$host_id" ]]; then
    echo "Couldn't find host $host_name for zone $zone_id"
    return 1
  else
    local url="zones/$zone_id/dns_records/$host_id"
    local data='{"type":"'$record_type'","name":"'$host_name'","content":"'$addr'"}'
    if [ $verbose ]; then echo "Updating record: $data" >&2; fi
    result=$(call_api "$url" PUT $data)
    if [[ $(echo "$result" | jq '.success') == "true" ]]; then
      echo "Updated $host_name $record_type to $addr" >&2
      touch_host "$host_name" $record_type "$addr"
    else
      echo "Error updating record" >&2
      echo "$result" | jq '.errors' >&2
    fi
  fi
}

set_ipv6_addr()
{
  local zone_id="$1"
  local host_name="$2"
  local addr="$3"
  update_record "$zone_id" "$host_name" "$addr" AAAA
}

set_ipv4_addr()
{
  local zone_id="$1"
  local host_name="$2"
  local addr="$3"
  update_record "$zone_id" "$host_name" "$addr" A
}

(which jq >/dev/null) || (echo "Please install 'jq'"; exit)

parse_args()
{
  while (( "$#" )); do
    case $1 in
      -h|--help)
        help
        exit
        ;;
      -v)
        verbose=$(($verbose + 1))
        echo "Enabling verbose mode... Level $verbose." >&2
        shift
        ;;
      -f)
        force_update=1
        shift
        ;;
      *)
        echo "GOT $1"
        conf=$1
        shift
        ;;
    esac
  done
}

parse_args "$@"

load_conf "$conf" || (help ; exit)

if [[ $use_v4 == "yes" ]]; then
  ipv4=$(get_ipv4)
  if [[ -z "$ipv4" ]]; then
    echo "Failed to get an IPv4 address" >&2
    use_ipv4="no"
  fi
fi

if [[ $use_v6 == "yes" ]]; then
  ipv6=$(get_ipv6)
  if [[ -z "$ipv6" ]]; then
    echo "Failed to get an IPv6 address" >&2
    use_ipv6="no"
  fi
fi

if [[ $use_v4 != "yes" && $use_v6 != "yes" ]]; then
  echo "Couldn't get an IPv4 or IPv6 address. Aborting!" >&2
  exit
fi

zone_id=$(get_zone "$zone")
if [[ -z $zone_id ]]; then
  echo "Couldn't find zone '$zone'"
  exit
fi

# Update IPv6
if [[ $use_v6 == "yes" ]]; then
  if [ $verbose ]; then echo "Setting IPv6" >&2; fi
  for host in $hosts; do
    set_ipv6_addr $zone_id $host $ipv6
  done
  if [ $verbose ]; then echo "" >&2; fi
fi

# Update IPv4
if [[ $use_v4 == "yes" ]]; then
  if [ $verbose ]; then echo "Setting IPv4" >&2; fi
  for host in $hosts; do
    set_ipv4_addr $zone_id $host $ipv4
  done
  if [ $verbose ]; then echo "" >&2; fi
fi
