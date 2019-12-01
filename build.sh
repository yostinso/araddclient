#!/bin/bash

version=1.0
files="araddclient araddclient.service araddclient.timer araddclient.conf.example Makefile README.md"

dir="araddclient-$version"
tarfile="araddclient_${version}.orig.tar.xz"
DEBEMAIL="yostinso@aradine.com" 
DEBFULLNAME="E.O. Stinson" 

if [[ $1 != "-u" ]]; then
  if [[ -d "$dir" ]]; then
    rm -r "$dir"
  fi
  if [[ -f "$tarfile" ]]; then
    rm "$tarfile"
  fi

  mkdir "$dir"

  for f in $files; do
    cp -v "$f" "$dir/"
  done
  ronn < araddclient.8.ronn > "$dir/araddclient.8" 2>/dev/null
  ronn < araddclient.conf.8.ronn > "$dir/araddclient.conf.8" 2>/dev/null

  (
    cd "$dir" &&
      DEBEMAIL="$DEBEMAIL" \
      DEBFULLNAME="$DEBFULLNAME" \
      dh_make --copyright gpl -i --createorig
  )
fi

debdir="$dir/debian"
cp debpostrm "$debdir/postrm"
rm \
  $debdir/README.Debian

generate_changelog()
{
  echo "araddclient (${version}-1) unstable; urgency=medium"
  echo ""
  git log --format="  * %s"
  echo ""
  echo " -- $DEBFULLNAME <$DEBEMAIL>  "$(date -R)
}

generate_changelog > $debdir/changelog

generate_docs()
{
  cp README.md "$debdir/README.source"
  echo "araddclient.8" > "$debdir/araddclient.manpages"
  echo "araddclient.conf.8" >> "$debdir/araddclient.manpages"
  echo "" >> "$debdir/README.source"
  echo " -- $DEBFULLNAME <$DEBEMAIL>  "$(date -R) >> "$debdir/README.source"
  sed -i -e 's/^# \(.*\)/\1\n----------------------/' "$debdir/README.source"
  (cd $debdir && ls -1 README*)
}

generate_docs > $debdir/araddclient-docs.docs

if [[ ! -f "$debdir/control.ex" ]]; then
  cp "$debdir/control" "$debdir/control.ex"
fi
generate_control()
{
  description="dynamic DNS updating client for Cloudflare DNS"
  long_desc=" This package provides a script and systemctl units for\n"
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

generate_control > "$debdir/control"

generate_copyright()
{
  cat debcopyright
}
generate_copyright > "$debdir/copyright"

if [[ ! -f "$debdir/rules.ex" ]]; then
  cp "$debdir/rules" "$debdir/rules.ex"
fi
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
generate_rules > "$debdir/rules"

rm "$debdir"/*.ex
(cd "$dir" &&
  DEBUILD_DPKG_BUILDPACKAGE_OPTS="-us -uc -I -i" \
  DEBUILD_LINTIAN_OPTS="-i -I --show-overrides --profile debian" \
  debuild
)

basename="araddclient_${version}-1.*"
if [[ -d debbuild ]]; then
  rm -r debbuild
fi
mkdir debbuild
mv -v \
  araddclient_${version}-1.* \
  araddclient_${version}-1_all.deb \
  araddclient_${version}-1_*.{build,changes} \
  araddclient_${version}.orig.tar.xz \
  debbuild/
