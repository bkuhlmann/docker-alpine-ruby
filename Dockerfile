# syntax=docker/dockerfile:1.3-labs

FROM bkuhlmann/alpine-base:2.5.0

LABEL description="Alchemists Alpine Ruby"
LABEL maintainer="brooke@alchemists.io"

RUN apk add --no-cache \
            g++ \
            gcc \
            gmp-dev \
            libc-dev \
            libffi-dev \
            make \
            postgresql-dev \
            postgresql-client \
            tzdata \
            yaml-dev \
            yaml

RUN <<STEPS
  set -o nounset
  set -o errexit
  set -o pipefail
  IFS=$'\n\t'
  mkdir -p /usr/local/etc
  printf "%s\n" "gem: --no-document" > /usr/local/etc/gemrc
STEPS

ENV LANG C.UTF-8
ENV RUBY_VERSION 3.2.2
ENV IMAGE_RUBY_SHA 4b352d0f7ec384e332e3e44cdbfdcd5ff2d594af3c8296b5636c710975149e23

# Dependencies:
# - https://bugs.ruby-lang.org/issues/11869
# - https://github.com/docker-library/ruby/issues/75
# Thread Patch:
# - https://github.com/docker-library/ruby/issues/196
# - https://bugs.ruby-lang.org/issues/14387#note-13 (patch source)
# - https://bugs.ruby-lang.org/issues/14387#note-16 (breaks glibc which doesn't matter here)
RUN <<STEPS
  # Defaults
  set -o nounset
  set -o errexit
  set -o pipefail
  IFS=$'\n\t'

  # Setup
  apk add --no-cache \
          --virtual .ruby-build-dependencies \
          autoconf \
          bison \
          bzip2 \
          bzip2-dev \
          coreutils \
          dpkg-dev dpkg \
          gcc \
          gdbm-dev \
          glib-dev \
          libc-dev \
          libffi-dev \
          libxml2-dev \
          libxslt-dev \
          linux-headers \
          make \
          ncurses-dev \
          openssl-dev \
          patch \
          procps \
          readline-dev \
          ruby \
          rust \
          tar \
          xz \
          zlib-dev

  # Download
  wget -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION::-2}/ruby-$RUBY_VERSION.tar.xz"
  echo "$IMAGE_RUBY_SHA *ruby.tar.xz" | sha256sum --check --strict
  mkdir -p /usr/src/ruby
  tar -xJf ruby.tar.xz --directory /usr/src/ruby --strip-components=1
  rm ruby.tar.xz

  # Patch
  cd /usr/src/ruby
  wget -O 'thread-stack-fix.patch' 'https://bugs.ruby-lang.org/attachments/download/7081/0001-thread_pthread.c-make-get_main_stack-portable-on-lin.patch'
  echo '3ab628a51d92fdf0d2b5835e93564857aea73e0c1de00313864a94a6255cb645 *thread-stack-fix.patch' | sha256sum --check --strict
  patch -p1 -i thread-stack-fix.patch
  rm thread-stack-fix.patch

  # Fix: "ENABLE_PATH_CHECK" is disabled to suppress warning: Insecure world writable dir
  echo '#define ENABLE_PATH_CHECK 0' > file.c.new
  echo >> file.c.new
  cat file.c >> file.c.new
  mv file.c.new file.c

  autoconf
  gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"

  # Fix: The configure script does not detect isnan/isinf as macros.
  export ac_cv_func_isnan=yes ac_cv_func_isinf=yes

  # Build
  ./configure --build="$gnuArch" --disable-install-doc --enable-yjit --enable-shared
  make --jobs="$(nproc)"
  make install
  runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
    | tr ',' '\n' \
    | sort -u \
    | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )"
  apk add --no-network \
          --virtual .ruby-run-dependencies \
          $runDeps
  apk del --no-network .ruby-build-dependencies

  # Clean
  cd /
  rm -r /usr/src/ruby
  ! apk --no-network list \
        --installed \
        | grep -v '^[.]ruby-run-dependencies' \
        | grep -i ruby
  [ "$(command -v ruby)" = '/usr/local/bin/ruby' ]

  # Test
  ruby --version
  gem --version
  bundle --version
STEPS

ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1
ENV BUNDLE_APP_CONFIG="$GEM_HOME"
ENV BUNDLE_JOBS=3
ENV BUNDLE_RETRY=3
ENV PATH $GEM_HOME/bin:$PATH
ENV RUBYOPT=-W:deprecated

RUN mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
RUN gem update --system

WORKDIR /usr/src/app
