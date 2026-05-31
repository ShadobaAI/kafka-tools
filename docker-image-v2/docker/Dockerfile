ARG BASE_IMAGE=debian:bookworm-slim

FROM ${BASE_IMAGE} AS runtime-base

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

FROM runtime-base AS edt-runtime-base

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      fontconfig \
      libasound2 \
      libgtk-3-0 \
      libxtst6 \
      openjdk-17-jre-headless \
  && rm -rf /var/lib/apt/lists/*


FROM runtime-base AS platform-runtime-base

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      ca-certificates \
      libgssapi-krb5-2 \
      libicu72 \
      libgsf-1-114 \
      locales \
      procps \
      unixodbc \
  && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

ENV LANG=ru_RU.UTF-8
ENV LANGUAGE=ru_RU:ru
ENV LC_ALL=ru_RU.UTF-8


FROM edt-runtime-base AS edt-installer-base

COPY docker/scripts/install-edt.sh /usr/local/sbin/onec-image/install-edt.sh


FROM platform-runtime-base AS platform-installer-base

COPY docker/scripts/install-platform.sh /usr/local/sbin/onec-image/install-platform.sh

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      unzip \
  && rm -rf /var/lib/apt/lists/*


FROM edt-installer-base AS edt-installer
ARG EDT_PLATFORM_SUPPORT

RUN --mount=type=bind,from=distr,source=.,target=/distr,readonly \
    bash /usr/local/sbin/onec-image/install-edt.sh /distr "${EDT_PLATFORM_SUPPORT}"

RUN find /opt/1C/1CE \( \
        -type d -name jmods -o \
        -type d -name include -o \
        -type d -name man -o \
        -type d -name demo -o \
        -type d -name legal \
      \) -prune -exec rm -rf {} + \
  && rm -rf /tmp/* /var/tmp/*

FROM platform-installer-base AS server-platform-installer
ARG PLATFORM_COMPONENTS=server,server_admin,ws,liberica_jre,ru

RUN --mount=type=bind,from=distr,source=.,target=/distr,readonly \
    bash /usr/local/sbin/onec-image/install-platform.sh /distr server "${PLATFORM_COMPONENTS}"

FROM platform-installer-base AS client-platform-installer
ARG PLATFORM_COMPONENTS=client_full,ru

RUN --mount=type=bind,from=distr,source=.,target=/distr,readonly \
    bash /usr/local/sbin/onec-image/install-platform.sh /distr client "${PLATFORM_COMPONENTS}"

FROM runtime-base AS oscript-installer

ENV OSCRIPTBIN=/opt/oscript/bin
ENV PATH="${OSCRIPTBIN}:${PATH}"

COPY docker/scripts/install-oscript.sh /usr/local/sbin/onec-image/install-oscript.sh

RUN --mount=type=bind,from=oscript,source=.,target=/oscript-distr,readonly \
    apt-get update \
  && apt-get install -y --no-install-recommends \
      ca-certificates \
      unzip \
  && bash /usr/local/sbin/onec-image/install-oscript.sh /oscript-distr \
  && rm -rf /var/lib/apt/lists/* /tmp/*

FROM edt-runtime-base AS edtcli
ARG EDT_VERSION
ARG REVISION

LABEL org.opencontainers.image.title="1C CI EDT CLI" \
      org.opencontainers.image.description="EDT CLI runtime for CI" \
      org.opencontainers.image.version="${EDT_VERSION}" \
      ru.shadobaai.onec.profile="edtcli" \
      ru.shadobaai.onec.edt-version="${EDT_VERSION}" \
      ru.shadobaai.onec.revision="${REVISION}"

COPY --from=edt-installer /opt/1C/1CE /opt/1C/1CE

RUN rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/lintian /usr/share/linda /tmp/* /var/tmp/*

ENV PATH="/opt/1C/1CE/components/1cedtcli:${JAVA_HOME}/bin:${PATH}"

WORKDIR /work

FROM platform-runtime-base AS ibcmd
ARG PLATFORM_VERSION
ARG REVISION

LABEL org.opencontainers.image.title="1C CI ibcmd" \
      org.opencontainers.image.description="1C server tools with OScript" \
      org.opencontainers.image.version="${PLATFORM_VERSION}" \
      ru.shadobaai.onec.profile="ibcmd" \
      ru.shadobaai.onec.platform-version="${PLATFORM_VERSION}" \
      ru.shadobaai.onec.revision="${REVISION}"

COPY --from=server-platform-installer /opt/1cv8 /opt/1cv8
COPY --from=oscript-installer /opt/oscript /opt/oscript

ENV OSCRIPTBIN=/opt/oscript/bin
ENV PATH="/opt/1cv8/current:${OSCRIPTBIN}:${PATH}"

RUN opm install vanessa-runner \
  && sed -i 's/#Использовать JSON/#Использовать json/g' /opt/oscript/lib/vanessa-runner/src/Модули/ГенерацияОтчетов.os \
  && rm -rf /root/.local/share/ovm /tmp/* /var/tmp/*

RUN find /opt/1cv8 \( \
        -type d -iname doc -o \
        -type d -iname docs -o \
        -type d -iname help -o \
        -type d -iname examples \
      \) -prune -exec rm -rf {} + \
  && rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/lintian /usr/share/linda /tmp/* /var/tmp/*

WORKDIR /work

FROM runtime-base AS client
ARG PLATFORM_VERSION
ARG REVISION

LABEL org.opencontainers.image.title="1C CI client" \
      org.opencontainers.image.description="1C client with OScript" \
      org.opencontainers.image.version="${PLATFORM_VERSION}" \
      ru.shadobaai.onec.profile="client" \
      ru.shadobaai.onec.platform-version="${PLATFORM_VERSION}" \
      ru.shadobaai.onec.revision="${REVISION}"

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      ca-certificates \
      dbus-x11 \
      fontconfig \
      libasound2 \
      libatk1.0-0 \
      libcups2 \
      libegl1 \
      libgl1 \
      libglu1-mesa \
      libgtk-3-0 \
      libicu72 \
      libsecret-1-0 \
      libwebkit2gtk-4.0-37 \
      libx11-6 \
      libxext6 \
      libxfixes3 \
      libxi6 \
      libxinerama1 \
      libxrandr2 \
      libxrender1 \
      libxtst6 \
      locales \
      net-tools \
      xvfb \
  && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

ENV LANG=ru_RU.UTF-8
ENV LANGUAGE=ru_RU:ru
ENV LC_ALL=ru_RU.UTF-8


COPY --from=client-platform-installer /opt/1cv8 /opt/1cv8
COPY --from=oscript-installer /opt/oscript /opt/oscript

ENV OSCRIPTBIN=/opt/oscript/bin
ENV PATH="/opt/1cv8/current:${OSCRIPTBIN}:${PATH}"

RUN opm install vanessa-runner \
  && sed -i 's/#Использовать JSON/#Использовать json/g' /opt/oscript/lib/vanessa-runner/src/Модули/ГенерацияОтчетов.os \
  && rm -rf /root/.local/share/ovm /tmp/* /var/tmp/*

RUN groupadd -r grp1cv8 --gid=999 \
  && useradd -r -g grp1cv8 --uid=999 --home-dir=/home/usr1cv8 --shell=/bin/bash usr1cv8 \
  && mkdir -p /home/usr1cv8/.1cv8 /var/1C/licenses \
  && chown -R usr1cv8:grp1cv8 /home/usr1cv8 /var/1C/licenses \
  && find /opt/1cv8 \( \
        -type d -iname doc -o \
        -type d -iname docs -o \
        -type d -iname help -o \
        -type d -iname examples \
      \) -prune -exec rm -rf {} + \
  && rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/lintian /usr/share/linda /tmp/* /var/tmp/*

ENV ONEC_LICENSE_DIR=/var/1C/licenses

VOLUME ["/var/1C/licenses", "/home/usr1cv8/.1cv8"]
WORKDIR /work
CMD ["bash"]

