FROM ubuntu:20.04 AS build
ARG UBNT_MIRROR=http://mirror.math.ucdavis.edu/ubuntu/
RUN sed -i -e "s|http://archive.ubuntu.com/ubuntu/|$UBNT_MIRROR|" /etc/apt/sources.list
RUN apt-get update && DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles apt-get install -y tzdata && apt-get install -y git build-essential dh-make devscripts bc ruby ruby-dev
RUN gem install ronn

FROM build AS build_result
WORKDIR /src
COPY README.md .gitignore build.sh Makefile araddclient* ./
COPY .git .git/
COPY pkg pkg/
COPY docs docs/
RUN ./build.sh -us

FROM ubuntu:20.04 AS base
WORKDIR /installs
COPY --from=build_result /src/debbuild/araddclient*.deb ./araddclient.deb
ARG UBNT_MIRROR=http://mirror.math.ucdavis.edu/ubuntu/
RUN sed -i -e "s|http://archive.ubuntu.com/ubuntu/|$UBNT_MIRROR|" /etc/apt/sources.list
RUN apt-get update && apt-get install -y jq curl dnsutils iproute2 && dpkg -i araddclient.deb && rm -rf /var/cache/apt/lists
WORKDIR /
RUN rm -r installs
COPY container_files/entry.sh /
# default sleep period 300 seconds
CMD [ "300" ]
ENTRYPOINT [ "/entry.sh" ]