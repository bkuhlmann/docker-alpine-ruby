# syntax = docker/dockerfile:1.4

FROM bkuhlmann/alpine-base:4.5.0

LABEL description="Alchemists Alpine Ruby"
LABEL maintainer="Brooke Kuhlmann <brooke@alchemists.io>"

ARG RUBY_VERSION=4.0.6
ARG RUBY_SHA=9c9d121fe3314ea7c801e690b9de981d2b9d12d7849db99c27482468a541ba0a

ENV LANG=C.UTF-8
ENV IRBRC=/usr/local/etc/irbrc

COPY lib/templates/gemrc.tt /usr/local/etc/gemrc
COPY lib/templates/irbrc.tt /usr/local/etc/irbrc

SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]

RUN apk add --no-cache \
            g++ \
            gmp-dev \
            libc-dev \
            libffi-dev \
            jemalloc \
            make \
            postgresql-dev \
            postgresql-client \
            sqlite \
            tzdata \
            yaml-dev \
            yaml

RUN <<STEPS
  # Install
  apk add --no-cache \
          --virtual .build-dependencies \
          autoconf \
          bzip2 \
          bzip2-dev \
          coreutils \
          dpkg-dev dpkg \
          gdbm-dev \
          glib-dev \
          libxml2-dev \
          libxslt-dev \
          linux-headers \
          ncurses-dev \
          openssl-dev \
          patch \
          procps \
          ruby \
          rust \
          wget \
          xz \
          zlib-dev

  # Download
  wget --quiet -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION::-2}/ruby-$RUBY_VERSION.tar.xz"
  echo "$RUBY_SHA *ruby.tar.xz" | sha256sum --check --strict
  mkdir -p /usr/src/ruby
  tar -xJf ruby.tar.xz --directory /usr/src/ruby --strip-components=1
  rm ruby.tar.xz

  # Thread Patch
  # - https://github.com/docker-library/ruby/issues/196
  # - https://bugs.ruby-lang.org/issues/14387#note-13 (patch source)
  # - https://bugs.ruby-lang.org/issues/14387#note-16 (breaks glibc which doesn't matter here)
  cd /usr/src/ruby
  wget --quiet -O "thread-stack-fix.patch" "https://bugs.ruby-lang.org/attachments/download/7081/0001-thread_pthread.c-make-get_main_stack-portable-on-lin.patch"
  echo '3ab628a51d92fdf0d2b5835e93564857aea73e0c1de00313864a94a6255cb645 *thread-stack-fix.patch' | sha256sum --check --strict
  patch -p1 -i thread-stack-fix.patch
  rm thread-stack-fix.patch

  autoconf
  gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"

  # Build
  ./configure --build="$gnuArch" \
              --disable-install-doc \
              --enable-shared ${rustArch:+--enable-yjit} ${rustArch:+--enable-zjit}
  make --jobs="$(nproc)"
  make install
  rm -rf /tmp/rust
  runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
    | tr ',' '\n' \
    | sort -u \
    | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )"
  apk add --no-network \
          --virtual .ruby-run-dependencies \
          $runDeps
  apk del --no-network .build-dependencies

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

ENV GEM_HOME="/usr/local/bundle"
ENV BUNDLE_SILENCE_ROOT_WARNING=1
ENV BUNDLE_APP_CONFIG="$GEM_HOME"
ENV BUNDLE_JOBS=3
ENV BUNDLE_RETRY=3
ENV PATH="$GEM_HOME/bin:$PATH"
ENV RUBYOPT="-W:deprecated -W:performance -W:strict_unused_block --yjit --debug-frozen-string-literal"
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2

RUN mkdir -p "$GEM_HOME" && chmod 1777 "$GEM_HOME"
RUN gem update --system

WORKDIR /usr/src/app
