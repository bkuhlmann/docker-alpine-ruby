FROM ruby:3.0.0-alpine3.13

LABEL description="Alpine Ruby"
LABEL maintainer="brooke@alchemists.io"

RUN apk update && \
    apk upgrade --available && \
    apk add --no-cache build-base \
                       postgresql-dev \
                       bash \
                       curl \
                       git \
                       gnupg \
                       openssl \
                       tzdata && \
    apk add --no-cache --update bash

ENV EDITOR=vim
ENV TERM=xterm
ENV BUNDLE_JOBS=3
ENV BUNDLE_RETRY=3

RUN git config --global init.defaultBranch master
RUN gem update --system

WORKDIR /usr/src/app
