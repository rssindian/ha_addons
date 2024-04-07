ARG BUILD_FROM=ghcr.io/hassio-addons/debian-base/amd64:7.3.3
ARG BUILD_ARCH
#ARG JACKETT_RELEASE=v0.21.2031

# Build arugments
ARG BUILD_DATE
ARG BUILD_REF
ARG BUILD_VERSION

FROM ${BUILD_FROM}

# Labels
LABEL \
    io.hass.name="VPN Jackett" \
    io.hass.description="Jackett via OpenVPN" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="addon" \
    maintainer="Rss" \
    org.label-schema.description="Jackett via OpenVPN" \
    org.label-schema.build-date="${BUILD_DATE}" \
    org.label-schema.name="VPN Jackett" \
    org.label-schema.schema-version="${BUILD_VERSION}" \
    org.label-schema.url="https://github.com/rssindian/ha_addons/jackett" \
    org.label-schema.usage="https://github.com/rssindian/ha_addons/jackett" \
    org.label-schema.vcs-ref="${BUILD_REF}" \
    org.label-schema.vcs-url="https://github.com/rssindian/" \
    org.label-schema.vendor="No Vendor"

ENV DEBIAN_FRONTEND noninteractive
ENV XDG_DATA_HOME="/config" \
    XDG_CONFIG_HOME="/config"

VOLUME /config

RUN usermod -u 99 nobody

WORKDIR /opt

# Install dependencies some of the scripts in the container rely on.
RUN apt update \
    && apt upgrade -y \
    && apt install -y  --no-install-recommends \
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
    procps \
    && apt-get clean \
    && apt autoremove -y \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

# Pull jackett binary
RUN \
  if [ -z ${JACKETT_RELEASE+x} ]; then \
	JACKETT_RELEASE=$(curl -sX GET "https://api.github.com/repos/Jackett/Jackett/releases/latest" \
	| jq -r .tag_name); \
  fi && \ 
  if [ $BUILD_ARCH = "armv7" ]; then \
    curl -o /opt/jacket.tar.gz -L https://github.com/Jackett/Jackett/releases/download/${JACKETT_RELEASE}/Jackett.Binaries.LinuxARM32.tar.gz; \
  elif [ $BUILD_ARCH = "aarch64" ]; then \
    curl -o /opt/jacket.tar.gz -L https://github.com/Jackett/Jackett/releases/download/${JACKETT_RELEASE}/Jackett.Binaries.LinuxARM64.tar.gz; \
  else \
    curl -o /opt/jacket.tar.gz -L https://github.com/Jackett/Jackett/releases/download/${JACKETT_RELEASE}/Jackett.Binaries.LinuxAMDx64.tar.gz; \
  fi 

#unzip
RUN tar -xzf /opt/jacket.tar.gz -C /opt 

# cleanup
RUN rm -rf /opt/jacket.tar.gz \
    && apt purge -y

ENV APP_NAME=vpnjackett

# Make directories
RUN mkdir -p /etc/jackett \
             /etc/openvpn \
             /config/${APP_NAME} 

#Move folders in this build
ADD openvpn/ /etc/openvpn/
ADD jackett/ /etc/jackett/

RUN chmod +x /etc/jackett/*.sh /etc/jackett/*.init /etc/openvpn/*.sh /opt/Jackett/jackett

EXPOSE 9117
CMD ["/bin/bash", "/etc/openvpn/start.sh"]

