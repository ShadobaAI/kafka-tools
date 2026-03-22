# ══════════════════════════════════════════════════════════════════════════════
# Stage 1: Установка платформы 1С
# ══════════════════════════════════════════════════════════════════════════════
FROM ubuntu:22.04 AS platform-installer

ARG PLATFORM_VERSION
ARG PLATFORM_DEB_ZIP

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -yq --no-install-recommends \
      locales \
      unzip \
      ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8

# deb64 — только нужные компоненты: common + server (ibcmd)
COPY ${PLATFORM_DEB_ZIP} /tmp/

RUN cd /tmp \
  # 8.3.27.2074 → 8.3.27-2074 (формат имён deb-пакетов)
  && DEB_VER="${PLATFORM_VERSION%.*}-${PLATFORM_VERSION##*.}" \
  && unzip -q $(basename "${PLATFORM_DEB_ZIP}") \
      "1c-enterprise-${PLATFORM_VERSION}-common_${DEB_VER}_amd64.deb" \
      "1c-enterprise-${PLATFORM_VERSION}-server_${DEB_VER}_amd64.deb" \
  && apt-get update \
  && apt-get install -yq --no-install-recommends \
      ./1c-enterprise-${PLATFORM_VERSION}-common_${DEB_VER}_amd64.deb \
      ./1c-enterprise-${PLATFORM_VERSION}-server_${DEB_VER}_amd64.deb \
  && rm -rf /tmp/*.deb /tmp/$(basename "${PLATFORM_DEB_ZIP}") \
  && rm -rf /var/lib/apt/lists/*

# ══════════════════════════════════════════════════════════════════════════════
# Stage 2: Установка EDT
# ══════════════════════════════════════════════════════════════════════════════
FROM ubuntu:22.04 AS edt-installer

ARG EDT_DISTR_TGZ

ENV DEBIAN_FRONTEND=noninteractive

# openjdk нужен только для запуска EDT installer
RUN apt-get update \
  && apt-get install -yq --no-install-recommends \
      locales \
      unzip \
      openjdk-17-jre-headless \
      libgtk-3-0 \
      libasound2 \
      libxtst6 \
  && rm -rf /var/lib/apt/lists/* \
  && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8

COPY ${EDT_DISTR_TGZ} /tmp/edt/

RUN cd /tmp/edt \
  && tar -xzf $(basename "${EDT_DISTR_TGZ}") \
  # .e1c.car — zip-архив, внутри data/1ce-installer-cli (нативный бинарник)
  && unzip -q 1c-enterprise-installer-*-linux-x86_64.e1c.car -d /tmp/edt-installer \
  && chmod +x /tmp/edt-installer/data/1ce-installer-cli \
  && /tmp/edt-installer/data/1ce-installer-cli install all \
      --source /tmp/edt \
      --ignore-hardware-checks \
      --ignore-signature-warnings \
  && ln -s "$(dirname "$(find /opt/1C/1CE -name ring | head -1)")" \
           /opt/1C/1CE/components/1c-enterprise-ring \
  && if find /opt/1C/1CE -name 1cedtcli | grep -q .; then \
       ln -s "$(dirname "$(find /opt/1C/1CE -name 1cedtcli | head -1)")" \
             /opt/1C/1CE/components/1cedtcli; \
     fi \
  && mkdir -p /etc/1C/1CE \
  && if [ ! -f /etc/1C/1CE/ring-commands.cfg ]; then touch /etc/1C/1CE/ring-commands.cfg; fi \
  && rm -rf /tmp/edt /tmp/edt-installer

# ══════════════════════════════════════════════════════════════════════════════
# Stage 3: Финальный образ — универсальный шаблон сборки
# ══════════════════════════════════════════════════════════════════════════════
FROM ubuntu:22.04

ARG PLATFORM_VERSION
ARG EDT_VERSION
ARG OSCRIPT_VERSION
ARG OSCRIPT_ZIP

LABEL description="1C Build image: Platform ${PLATFORM_VERSION} + EDT ${EDT_VERSION} + OScript ${OSCRIPT_VERSION} + vrunner"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -yq --no-install-recommends \
      locales \
      ca-certificates \
      libgtk-3-0 \
      fontconfig \
      unixodbc \
      libicu-dev \
      unzip \
  && rm -rf /var/lib/apt/lists/* /var/cache/debconf \
  && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8

ENV LANG=ru_RU.UTF-8
ENV LANGUAGE=ru_RU:ru
ENV LC_ALL=ru_RU.UTF-8

# ── Платформа 1С ──────────────────────────────────────────────────────────────
COPY --from=platform-installer /opt/1cv8 /opt/1cv8

# ── EDT (включает bundled JRE) ────────────────────────────────────────────────
COPY --from=edt-installer /opt/1C/1CE /opt/1C/1CE
COPY --from=edt-installer /etc/1C/1CE/ring-commands.cfg /etc/1C/1CE/ring-commands.cfg

# JAVA_HOME — bundled JRE внутри EDT (симлинк не зависит от версии)
RUN ln -s "$(dirname "$(dirname "$(find /opt/1C/1CE/components -name java -type f | head -1)")")" \
          /opt/1C/1CE/jre
ENV JAVA_HOME=/opt/1C/1CE/jre
ENV PATH="/opt/1cv8/x86_64/${PLATFORM_VERSION}:/opt/1C/1CE/components/1c-enterprise-ring:/opt/1C/1CE/components/1cedtcli:/opt/oscript/bin:${JAVA_HOME}/bin:${PATH}"

# ── OScript (локальный дистрибутив, .NET) ─────────────────────────────────────
COPY ${OSCRIPT_ZIP} /tmp/
RUN unzip -q /tmp/$(basename "${OSCRIPT_ZIP}") -d /opt/oscript \
  && chmod +x /opt/oscript/bin/oscript /opt/oscript/bin/opm \
  && rm /tmp/$(basename "${OSCRIPT_ZIP}")

# ── vanessa-runner ────────────────────────────────────────────────────────────
RUN opm install vanessa-runner

WORKDIR /build

# скрипт сборки монтируется снаружи — образ универсальный
ENTRYPOINT ["/bin/bash"]
