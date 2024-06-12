# syntax=docker/dockerfile:1.3-labs

FROM bkuhlmann/alpine-base:3.6.0

LABEL description="Alchemists Alpine Ruby"
LABEL maintainer="brooke@alchemists.io"

ENV LANG C.UTF-8
ENV RUBY_VERSION 3.3.3
ENV IMAGE_RUBY_SHA 83c0995388399c9555bad87e70af069755b5a9d84bbaa74aa22d1e37ff70fc1e
ENV IRBRC /usr/local/etc/irbrc

COPY lib/templates/gemrc.tt /usr/local/etc/gemrc
COPY lib/templates/irbrc.tt /usr/local/etc/irbrc

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
          ruby \
          rust \
          tar \
          xz \
          zlib-dev

  # Rust
  rustArch=
  apkArch="$(apk --print-arch)"
  case "$apkArch" in
    'x86_64') rustArch='x86_64-unknown-linux-musl'; rustupUrl='https://static.rust-lang.org/rustup/archive/1.26.0/x86_64-unknown-linux-musl/rustup-init'; rustupSha256='7aa9e2a380a9958fc1fc426a3323209b2c86181c6816640979580f62ff7d48d4';;
    'aarch64') rustArch='aarch64-unknown-linux-musl'; rustupUrl='https://static.rust-lang.org/rustup/archive/1.26.0/aarch64-unknown-linux-musl/rustup-init'; rustupSha256='b1962dfc18e1fd47d01341e6897cace67cddfabf547ef394e8883939bd6e002e';;
  esac;

  if [ -n "$rustArch" ]; then
    mkdir -p /tmp/rust
    wget -O /tmp/rust/rustup-init "$rustupUrl"
    echo "$rustupSha256 */tmp/rust/rustup-init" | sha256sum --check --strict
    chmod +x /tmp/rust/rustup-init
    export RUSTUP_HOME='/tmp/rust/rustup' CARGO_HOME='/tmp/rust/cargo'
    export PATH="$CARGO_HOME/bin:$PATH"
    /tmp/rust/rustup-init -y --no-modify-path --profile minimal --default-toolchain '1.74.1' --default-host "$rustArch"
    rustc --version
    cargo --version
  fi;

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
  ./configure --build="$gnuArch" --disable-install-doc --enable-shared ${rustArch:+--enable-yjit}
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
ENV RUBYOPT="-W:deprecated -W:performance --yjit --debug-frozen-string-literal"

RUN mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
RUN gem update --system

WORKDIR /usr/src/app
