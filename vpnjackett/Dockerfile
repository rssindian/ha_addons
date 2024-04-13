ARG BUILD_FROM=ghcr.io/hassio-addons/debian-base/amd64:7.3.3
ARG BUILD_ARCH
#ARG JACKETT_RELEASE=v0.21.2031

# Build arugments
ARG BUILD_DATE
ARG BUILD_REF
ARG BUILD_VERSION

FROM ${BUILD_FROM}

ENV DEBIAN_FRONTEND noninteractive
ENV APP_NAME="vpnjackett"

VOLUME /config

RUN usermod -u 99 nobody

WORKDIR /opt

# Install dependencies some of the scripts in the container rely on.
RUN apt update \
    && apt upgrade -y \
    && apt install -y --no-install-recommends \
    curl \
    ca-certificates \
    dos2unix \
    inetutils-ping \
    ipcalc \
    iptables \
    jq \
    kmod \
    moreutils \
    net-tools \
    openresolv \
    openvpn \
    procps

# Add bullseye source for libicu and ip
RUN echo "deb http://deb.debian.org/debian/ bullseye main contrib non-free" >> /etc/apt/sources.list \
    && apt update \
    && apt install -y --no-install-recommends \
    iproute2 \
    libicu67

# Remove bullseye source
RUN sed -i.bak '/deb http:\/\/deb.debian.org\/debian\/ bullseye main contrib non-free/d' /etc/apt/sources.list \
&& apt update

# Pull jackett binary
RUN \
  if [[ -z ${JACKETT_RELEASE+x} ]]; then \
	JACKETT_RELEASE=$(curl -sX GET "https://api.github.com/repos/Jackett/Jackett/releases/latest" | jq -r .tag_name); \
  fi && \ 
  if [[ "$BUILD_ARCH" = "armv7" ]]; then \
    curl -o /opt/jacket.tar.gz -L https://github.com/Jackett/Jackett/releases/download/${JACKETT_RELEASE}/Jackett.Binaries.LinuxARM32.tar.gz; \
  elif [[ "$BUILD_ARCH" = "aarch64" ]]; then \
    curl -o /opt/jacket.tar.gz -L https://github.com/Jackett/Jackett/releases/download/${JACKETT_RELEASE}/Jackett.Binaries.LinuxARM64.tar.gz; \
  else \
    curl -o /opt/jacket.tar.gz -L https://github.com/Jackett/Jackett/releases/download/${JACKETT_RELEASE}/Jackett.Binaries.LinuxAMDx64.tar.gz; \
  fi 

#unzip
RUN tar -xzf /opt/jacket.tar.gz -C /opt 

# cleanup
 RUN rm -rf /opt/jacket.tar.gz \
    && apt clean \
    && apt autoremove -y \
    && apt purge -y \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

#Move folders in this build
ADD rootfs/ /

RUN chmod +x /etc/jackett/*.sh /etc/jackett/*.init /etc/openvpn/*.sh /opt/Jackett/jackett

CMD ["/etc/openvpn/init.sh"]
