#!/bin/bash

default_version=1.0
version_increment=0.01
prefix=araddclient
DEBEMAIL="yostinso@aradine.com"
DEBFULLNAME="E.O. Stinson"

help()
{
  echo "" >&2
  echo "build.sh -- Debian package builder for araddclient" >&2
  echo "" >&2
  echo "Usage:" >&2
  echo "  ./build.sh [-u] [-r] [-v n.nn]" >&2
  echo ""
  echo "  -r    Create new version at HEAD and update the release tag" >&2
  echo "  -u    Don't delete the build folder before running" >&2
  echo "  -v    Increment the version by n.nn instead of $version_increment" >&2
  echo "  -us   Skip signing" >&2
  echo ""
}

parse_args()
{
  while (( "$#" )); do
    case $1 in
      -r)
        set_release_tag=1
        shift
        ;;
      -u)
        update_only=1
        shift
        ;;
      -v)
        version_increment=$2
        shift 2
        ;;
      -us)
        skip_signing="-uc -us"
        shift
        ;;
      *)
        help
        exit
        ;;
    esac
  done
}

get_build_version()
{
  local head_version=$(git tag -l v* --points-at HEAD | sed -e 's/^v//' | sort -n)
  if [[ -z $head_version ]]; then
    local last_version=$(get_versions | head -n 1)
    get_next_version $last_version
  else
    echo $head_version
  fi
}

get_versions()
{
  git tag -l v* | sed -e 's/^v//' | sort -n -r
}

get_next_version()
{
  local last=$1
  echo "$1 + $version_increment" | bc
}

generate_changes_for()
{
  local version=$1
  local last_hash=$2
  local cur_hash=$3

  echo "araddclient (${version}-ubuntu1) unstable; urgency=medium"
  echo ""
  git log --format="  * %s" $last_hash..$cur_hash --
  echo ""
  echo " -- $DEBFULLNAME <$DEBEMAIL>  "$(date -R)
  echo ""
}

generate_changelog()
{
  local first_hash=$(git rev-list --max-parents=0 HEAD)

  local cur_version=$(get_versions | head -n 1)
  local cur_hash=$(git show -s --format="%H" v$cur_version)
  local next_version=$(get_next_version $cur_version)

  generate_changes_for $next_version $cur_hash HEAD

  local v
  local prev_hash
  local cur_hash
  cur_version=""
  for v in $(get_versions); do
    prev_hash=$(git show -s --format="%H" v$v)
    if [[ ! -z $cur_version ]]; then
      generate_changes_for $cur_version $prev_hash $cur_hash
    fi
    cur_version=$v
    cur_hash=$prev_hash
  done

  generate_changes_for $cur_version $first_hash $cur_hash
}

generate_docs()
{
  echo "araddclient.8" > "$debdir/araddclient.manpages"
  echo "araddclient.conf.8" >> "$debdir/araddclient.manpages"
  echo "" >> "$debdir/README.source"
  echo " -- $DEBFULLNAME <$DEBEMAIL>  "$(date -R) >> "$debdir/README.source"
  sed -i -e 's/^# \(.*\)/\1\n----------------------/' "$debdir/README.source"
  (cd $debdir && ls -1 README*)
}

generate_control()
{
  local description="dynamic DNS updating client for Cloudflare DNS"
  local long_desc=" This package provides a script and systemctl units for\n"
  long_desc="${long_desc} updating Cloudflare DNS dynamically.\n .\n"
  long_desc="${long_desc} It supports fetching IPs from interfaces, icanhazip,\n"
  long_desc="${long_desc} and Meraki MXes using the local status page.\n .\n"
  long_desc="${long_desc} It only supports the Cloudflare API for updates, and\n"
  long_desc="${long_desc} the user must provide API credentials (OAuth is\n"
  long_desc="${long_desc} not supported."
  sed \
    -e 's/^Section: .*/Section: net/' \
    -e 's/^Standards-Version: .*/Standards-Version: 3.9.7/' \
    -e 's!^Homepage: .*!Homepage: https://github.com/yostinso/araddclient!' \
    -e 's!^#Vcs-Git:.*!Vcs-Git: https://github.com/yostinso/araddclient.git!' \
    -e 's!^#Vcs-Browser:.*!Vcs-Browser: https://github.com/yostinso/araddclient!' \
    -e 's/^Depends: .*/Depends: jq (>=1.5), bash (>=4.3), curl (>=7.47), ${misc:Depends}/' \
    -e 's/Description: .*/Description: '"$description"'/' \
    -e '/^Description: .*/{n; c \
'"$long_desc"'
    }' \
    "$debdir/control.ex"
}

generate_rules()
{
   cat "$debdir/rules.ex"
  # -e '\!^# see!a export DESTDIR="'"$debdir/araddclient"'"' \
  sed \
    -e '\!generated override targets!a \
override_dh_auto_install:\
	dh_auto_install -- prefix=/usr' \
    "$debdir/rules.ex"
}

do_prepare()
{
  local version="$1"
  local dir="$2"
  local files="$3"
  local manpages="$4"

  local tarfile="${prefix}_${version}.orig.tar.xz"

  if [[ ! $update_only ]]; then
    for d in $prefix-[0-9]*; do
      if [[ -d "$d" ]]; then
        echo "Removing $d"
        rm -r "$d"
      fi
    done
    for tf in $prefix_*.orig.tar.xz; do
      if [[ -f "$tf" ]]; then
        rm -v "$tf"
      fi
    done
  fi
  if [[ ! -d "$dir" ]]; then
    mkdir "$dir"
  fi

  cp -v $files "$dir/"
  for f in $manpages; do
    ronn < "docs/${f}.ronn" > "$dir/$f" 2>/dev/null || return 0
    ls "$dir/$f"
  done
}

do_dh_make()
{
  local dir="$1"
  local debdir="$2"
  (
    cd "$dir" &&
      DEBEMAIL="$DEBEMAIL" \
      DEBFULLNAME="$DEBFULLNAME" \
      dh_make -y --copyright gpl -i --createorig
  )
  [[ -f "$debdir/README.Debian" ]] || {
    echo "dh_make aborted or failed";
    return 1;
  }
  rm "$debdir/README.Debian"
  if [[ ! -f "$debdir/control.ex" ]]; then
    cp "$debdir/control" "$debdir/control.ex"
  fi
  if [[ ! -f "$debdir/rules.ex" ]]; then
    cp "$debdir/rules" "$debdir/rules.ex"
  fi
}

relocate_build()
{
  local folder="$1"
  local version="$2"
  local distro="ubuntu"
  (
    cd "$folder"
    if [[ -d debbuild ]]; then
      rm -r debbuild
    fi
    mkdir debbuild
    mv -v \
      araddclient_${version}-${distro}1.* \
      araddclient_${version}-${distro}1_all.deb \
      araddclient_${version}-${distro}1_*.{build,changes} \
      araddclient_${version}.orig.tar.xz \
      debbuild/
  )
}

parse_args "$@"
files="araddclient araddclient.service araddclient.timer docs/araddclient.conf.example Makefile README.md"
manpages="araddclient.8 araddclient.conf.8"

# Prepare files
version=$(get_build_version)
dir="$prefix-$version"
debdir="$dir/debian"
do_prepare "$version" "$dir" "$files" "$manpages" || exit

# Docs
do_dh_make "$dir" "$debdir" || exit
cp README.md "$debdir/README.source" || exit
generate_docs > "$debdir/araddclient-docs.docs" || exit

# Static package scripts
cp pkg/* "$debdir/" || exit

# Other files
generate_changelog > "$debdir/changelog" || exit
generate_control > "$debdir/control" || exit
generate_rules > "$debdir/rules" || exit

gpg-agent || gpg-agent --daemon
# Generate build
(cd "$dir" &&
  rm debian/*.ex # Clean up example files
  DEBUILD_DPKG_BUILDPACKAGE_OPTS="-us -uc -I -i" \
  DEBUILD_LINTIAN_OPTS="-i -I --show-overrides --profile debian" \
  debuild $skip_signing
) || exit

# Clean up root folder and move generated files into debbuild
relocate_build $(dirname "$0") "$version" || exit

if [[ "$set_release_tag" ]]; then
  git tag v$version HEAD || exit
  git tag -f release HEAD || exit
fi
