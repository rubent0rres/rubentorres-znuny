# Znuny Docker Image - Multi-stage build
# Basado en andrey-n-safonov/znuny-dockerized (MIT). Modificado para Znuny 7.3.4.
# Stage 1: Base image with system dependencies (cache forever)
FROM debian:12-slim AS base

LABEL maintainer="local-build"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install system dependencies (cache forever)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    rsync \
    wget \
    lsb-release \
    apache2 \
    libapache2-mod-perl2 \
    mariadb-client \
    perl \
    supervisor \
    cron \
    && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends postgresql-client-16 \
    && \
    rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc/* \
    && rm -rf /usr/share/man/* \
    && rm -rf /var/cache/apt/* \
    && rm -rf /var/tmp/*

# Stage 2: Znuny application (rebuild when version changes)
FROM base AS app

ENV ZNUNY_HOME=/opt/znuny

LABEL description="Znuny - Open Source Ticket System"

# Install Znuny Perl dependencies (cached independently of the Znuny version)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libdbd-mysql-perl \
    libdbd-pg-perl \
    libdbd-odbc-perl \
    libarchive-zip-perl \
    libcrypt-eksblowfish-perl \
    libcrypt-ssleay-perl \
    libdatetime-perl \
    libencode-hanextra-perl \
    libio-socket-ssl-perl \
    libjson-xs-perl \
    liblist-allutils-perl \
    libmailtools-perl \
    libmoo-perl \
    libnamespace-clean-perl \
    libnet-dns-perl \
    libnet-ldap-perl \
    libtemplate-perl \
    libtext-csv-xs-perl \
    libtimedate-perl \
    libxml-libxml-perl \
    libxml-libxslt-perl \
    libyaml-libyaml-perl \
    libauthen-sasl-perl \
    libauthen-ntlm-perl \
    libcss-minifier-xs-perl \
    libjavascript-minifier-xs-perl \
    libemail-valid-perl \
    libgd-perl \
    libgd-graph-perl \
    libmime-tools-perl \
    libpdf-api2-perl \
    libsoap-lite-perl \
    libspreadsheet-xlsx-perl \
    libxml-parser-perl \
    libuuid-perl \
    libmail-imapclient-perl \
    libhash-merge-perl \
    libical-parser-perl \
    cpanminus \
    build-essential \
    && rm -rf /usr/share/doc/* \
    && rm -rf /usr/share/man/* \
    && cpanm --notest Data::UUID \
    && rm -rf /root/.cpanm \
    && apt-get purge -y build-essential \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/* \
    && rm -rf /var/tmp/*

# Znuny version — build ARG so it can be overridden (--build-arg ZNUNY_VERSION=x.y.z)
ARG ZNUNY_VERSION=7.3.4
ENV ZNUNY_VERSION=${ZNUNY_VERSION}

# Download and extract Znuny from the official release server (keeps the repo light
# and makes multi-arch builds self-contained — no local tarball needed).
RUN cd /opt \
    && curl -fSL "https://download.znuny.org/releases/znuny-${ZNUNY_VERSION}.tar.gz" -o /tmp/znuny.tar.gz \
    && tar xzf /tmp/znuny.tar.gz \
    && mv znuny-${ZNUNY_VERSION} znuny \
    && rm /tmp/znuny.tar.gz \
    && cd ${ZNUNY_HOME} \
    && rm -rf scripts/test/ \
    && rm -rf scripts/contrib/ \
    && rm -rf doc/ \
    && rm -rf var/logo/ \
    && find . -name "*.md" -type f -delete \
    && find . -name "*.pod" -type f -delete \
    && find /usr/share/perl* -type d -name 'examples' -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/share/perl* -type d -name 'demo' -exec rm -rf {} + 2>/dev/null || true

# Create znuny user, set permissions, configure Apache, create directories
RUN useradd -r -d ${ZNUNY_HOME} -c 'Znuny user' -s /bin/bash znuny \
    && usermod -G www-data znuny \
    && ${ZNUNY_HOME}/bin/otrs.SetPermissions.pl \
    && a2dissite 000-default \
    && a2enmod perl \
    && a2enmod deflate \
    && a2enmod filter \
    && a2enmod headers \
    && mkdir -p ${ZNUNY_HOME}/var/tmp \
        ${ZNUNY_HOME}/var/article \
        ${ZNUNY_HOME}/var/log \
        ${ZNUNY_HOME}/var/run \
        ${ZNUNY_HOME}/var/sessions \
        ${ZNUNY_HOME}/var/spool \
    && chown -R znuny:www-data ${ZNUNY_HOME}/var \
    && mkdir -p /var/log/supervisor

# Stage 3: Final image with configuration (rebuild frequently)
FROM app AS config

COPY apache-znuny.conf /etc/apache2/sites-available/znuny.conf
COPY supervisord.conf /etc/supervisor/conf.d/znuny.conf

COPY docker-entrypoint.sh /usr/local/bin/
COPY autoinstall.sh /usr/local/bin/
COPY upgrade.sh /usr/local/bin/

RUN a2ensite znuny \
    && chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/autoinstall.sh /usr/local/bin/upgrade.sh \
    && cp -a ${ZNUNY_HOME} /opt/znuny-dist

EXPOSE 80

VOLUME ["${ZNUNY_HOME}"]

WORKDIR ${ZNUNY_HOME}

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
