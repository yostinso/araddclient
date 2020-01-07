# araddclient

A dynamic DNS client for Cloudflare A/AAAA records

## Installing
### Dependencies
At a minimum, this script requires `bash`, `curl`, and `jq` (for parsing Cloudflare API responses.)

## From the help
```
araddclient -- dynamic DNS client for v4/v6 updates to Cloudflare

Usage:
  ./araddclient [-v] [-v] [-v] [-f] config.conf

        Uses config.conf in the script's folder by default.
  -v    Verbose output. Level 3 includes API debugging and therefore passwords.
  -f    Force update regardless of age or matching IP
```

## Configuration files
### Example config
```sh
# Cloudflare server (probably never changes)
server=api.cloudflare.com/client/v4

# Cloudflare credentials (email and auth key)
login=your@email.here
password=aaabbbeeefffccceeefff

# Cloudflare zone your records live in
zone=myserver.com
# Space-separated list of host records to update
hosts="myserver.com www.myserver.com"

# Configuring updates
update_frequency=300    # How frequently to send an IP update (when changed); default is 300 seconds.
state_dir=/tmp          # Where to store state; default is /var/lib/araddclient.

use_v4=yes              # Attempt to update A records. Default yes.
v4_method=icanhazip     # icanhazip (default), meraki, or a custom function.
allow_create=no         # If a host entry doesn't yet exist, create one

use_v6=no               # Attempt to update AAAA records. Default no.
v6_method=ifaddr        # ifaddr (default), icanhazip, or a custom function.
v6_if=eth0              # The interface to get an IP from when using ifaddr
```

### Minimal IPv4-only config
```sh
server=api.cloudflare.com/client/v4
login=your@email.here
password=aaabbbeeefffccceeefff
zone=myserver.com
hosts="myserver.com"
```

### Minimal config for IPv4 & IPv6
```sh
server=api.cloudflare.com/client/v4
login=your@email.here
password=aaabbbeeefffccceeefff
zone=myserver.com
hosts="myserver.com"
use_v6=yes
v6_if=eth0
```

### Custom IP discovery
For either `v4_method` or `v6_method`, you can supply a custom function. This is possible because the 
config file is just loaded with `bash`'s `source` keyword. The method will be passed "4" or "6" as the
first argument, depending on the protocol.

For example:
```sh
v4_method=mymethod
mymethod()
{
  local protocol_ver="$1"
  echo "Magic custom method" >&2  # only log to stderr
  curl -s http://10.0.0.1/index.json | jq -r ".result.${protocol_ver}.ip"
}
```
