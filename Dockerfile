FROM ubuntu:20.04 AS os
LABEL vendor="telesoho" tag="telesoho/dockerodoo" version="1.0"

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

ARG TARGETPLATFORM
ARG BUILDPLATFORM
RUN echo "I am running on $BUILDPLATFORM, building for $TARGETPLATFORM" > /log

# Generate locale C.UTF-8 for postgres and general locale data
ENV LANG C.UTF-8

# Install some deps, lessc and less-plugin-clean-css, and wkhtmltopdf
RUN apt-get update && apt-get upgrade -y
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  dirmngr \
  fonts-noto-cjk \
  gnupg \
  gsfonts \
  libssl-dev \
  node-less \
  python3-num2words \
  python3-pdfminer \
  python3-pip \
  python3-phonenumbers \
  python3-pyldap \
  python3-openssl \
  python3-qrcode \
  python3-renderpm \
  python3-setuptools \
  python3-slugify \
  python3-vobject \
  python3-watchdog \
  python3-xlrd \
  python3-xlwt \
  xz-utils \
  dumb-init \
  lsb-release


RUN  apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  libffi-dev  \
  libjpeg-dev \
  libldap2-dev \
  libpq-dev \
  libsasl2-dev \
  libxml2-dev \
  libxslt1-dev \
  libxslt-dev \
  libzip-dev \
  lsb-release \
  python3-dev  \
  python3-wheel \
  python3 \
  sudo

# Install fonts
RUN apt-get update && apt-get install -y  \
  # JAPANESE FONTS
  fonts-noto \
  # fonts-ipafont \
  # fonts-ipaexfont \
  # fonts-vlgothic \
  fonts-takao \
  # fonts-hanazono \
  # fonts-horai-umefont \
  # fonts-komatuna \
  # fonts-konatu \
  # fonts-migmix \
  # fonts-motoya-l-cedar \
  # fonts-motoya-l-maruberi \
  # fonts-mplus \
  # fonts-sawarabi-gothic \
  # fonts-sawarabi-mincho \
  # fonts-umeplus \
  # fonts-dejima-mincho \
  # fonts-misaki \
  # fonts-mona \
  # fonts-monapo \
  # fonts-oradano-mincho-gsrr \
  # fonts-kiloji \
  # fonts-mikachan \
  # fonts-seto \
  # fonts-yozvox-yozfont \
  # fonts-aoyagi-kouzan-t \
  # fonts-aoyagi-soseki \
  # fonts-kouzan-mouhitsu \
  # CHINESE FONTS
  fonts-wqy-microhei \
  ttf-wqy-zenhei \
  python3-venv \
  git


RUN apt-get install -y --no-install-recommends ssh ffmpeg

# Install postgresql-client
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN apt update && apt install -yq postgresql-client


RUN dpkgArch="$(dpkg --print-architecture)"; \
  release="$(lsb_release -cs)"; \
  curl -o wkhtmltox.deb -L "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.${release}_${dpkgArch}.deb" \
  && apt-get install -y --no-install-recommends ./wkhtmltox.deb \
  && rm -rf wkhtmltox.deb


# Install rtlcss (on Debian buster)
RUN apt-get update && apt-get install -y --no-install-recommends npm
RUN npm config set registry "http://registry.npm.taobao.org" && npm install -g rtlcss

FROM os as odoo

# Switch to user odoo to create the folders mapped with volumes, else the
# corresponding folders will be created by root on the host

# Create the odoo user
RUN useradd --create-home --home-dir /opt/odoo --no-log-init odoo

USER odoo

RUN /bin/bash -c "mkdir -p /opt/odoo/{etc,src/odoo,custom,data,ssh}"

# Install odoo src
ARG ODOO_COMMIT_ID=15.0
ARG ODOO_SHA=
# RUN curl -H "Authorization: token $github_token"

WORKDIR /opt/odoo/src
RUN curl -o odoo.tgz -L https://github.com/odoo/odoo/tarball/${ODOO_COMMIT_ID} \
    && if [ "${ODOO_SHA}" != "" ]; then echo "${ODOO_SHA} odoo.tgz" | sha1sum -c - ;fi\
    && tar --transform='s|^odoo-odoo-[^\/]*|odoo|' -xzf odoo.tgz \
    && rm odoo.tgz

USER odoo

WORKDIR /opt/odoo

RUN python3 -m venv venv
RUN /opt/odoo/venv/bin/pip install --upgrade pip
# Install Odoo python dependencies
RUN /opt/odoo/venv/bin/pip install -r /opt/odoo/src/odoo/requirements.txt

COPY requirements.txt requirements.txt
RUN /opt/odoo/venv/bin/pip install -r /opt/odoo/requirements.txt
# Startup script for custom setup
# ADD startup.sh /opt/scripts/startup.sh

FROM odoo as odoo_staging
RUN /opt/odoo/venv/bin/pip install flake8 black
USER 0

RUN dpkgArch="$(dpkg --print-architecture)"; \
  if [[ "$dpkgArch" != "amd64" ]]; then apt-get install -y --no-install-recommends chromium-browser; \
  else curl -o google-chrome.deb -L "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
  && apt-get install -f -y ./google-chrome.deb \
  && rm -rf google-chrome.deb; fi


VOLUME [ \
  "/opt/odoo/etc", \
  "/opt/odoo/custom", \
  "/opt/odoo/data", \
  "/opt/odoo/ssh", \
  "/opt/scripts" \
  ]

# Expose Odoo services
EXPOSE 8069 8071 8072


COPY boot /usr/bin/boot
COPY save_environ /usr/bin/save_environ
COPY startup_common /usr/bin/startup_common
RUN chmod +x /usr/bin/save_environ /usr/bin/startup_common /usr/bin/boot

ENTRYPOINT [ "/usr/bin/dumb-init", "/usr/bin/boot" ]


# clean
RUN rm -rf /var/lib/apt/lists/*
