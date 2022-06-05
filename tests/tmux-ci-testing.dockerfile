#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
# Base environment for testing
#
# Using a stable Debian release since we don't want testing to rely on new
# features that users might not have. Using the slim variant since we want
# a minimalist yet realistic testing environment.
#
# NOTE: this image does *not* include tmux, since we will want to test how the
# script works when tmux is not avialble.
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#

FROM debian:stable-slim

ARG TEST_USER="airline"
ARG TEST_UID="1000"
ARG TEST_GID="100"

LABEL maintainer="Andrew Stryker <axs@sdf.org>"

ENV HOME=/home/$TEST_USER
ENV PLUGIN_HOME=$HOME/.tmux/plugins/tmux-airline

# We need additional packages:
#   - tmux, obviously
#   - bats, a simple testing suite particularly for Bash scripts
#   - git (and dependancies), for CI integrations
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        tmux \
        bats \
        git

# Create a non-priveleged user
#
# Not scrictly necessary. However, we want the testing environment to closely
# mirror the application environment.
RUN useradd \
      -d $HOME \
      -g $TEST_GID \
      -u $TEST_UID \
      -s /bin/bash \
      $TEST_USER && \
    mkdir $HOME && \
    chown $TEST_UID:$TEST_GID $HOME && \
    mkdir -p $PLUGIN_HOME && \
    ln -s $PLUGIN_HOME $HOME

# Fix permissions
RUN chown --recursive $TEST_UID:$TEST_GID $HOME

# Switch to non-priveleged user
USER $TEST_UID:$TEST_GID
WORKDIR $PLUGIN_HOME

#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#
