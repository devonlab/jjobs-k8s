# J-Jobs 
#
# Copyright (c) LG CNS and/or its affiliates. All rights reserved.

# Pull base image
# ---------------
FROM amazonlinux:2023 as base

# Maintainer
# ----------
MAINTAINER J-Jobs <j-jobs@lgcns.com>

# Environment variables required for this build (do NOT change)
# -------------------------------------------------------------

# Custom Environment variables
# -------------------------------------------------------------
ENV WORKING_DIR=/working

# Install Util
# -------------------------------------------------------------
RUN dnf update -y && dnf clean all \
    && dnf -y install openssh-server openssh-clients \
    hostname \
    tar \
    ncurses \
    net-tools \
    zip unzip \
    procps \
    telnet \
    passwd

RUN mkdir /var/run/sshd \
    && ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N ''

# Add User : jjobs
# -------------------------------------------------------------
RUN groupadd jjobs \
    && useradd jjobs -g jjobs \
    && echo 'jjobs1234' | passwd --stdin root \
    && echo 'jjobs1234' | passwd --stdin jjobs \
    && mkdir -p /engn001/jjobs \
    && mkdir -p /logs001/jjobs \
    && mkdir -p $WORKING_DIR \
    && chown -R jjobs:jjobs /engn001 \
    && chown -R jjobs:jjobs /logs001 \
    && chown -R jjobs:jjobs $WORKING_DIR


# Copy files needed during both installation and runtime
# -------------
COPY shell/entrypoint.sh /entrypoint.sh
COPY shell/test-case1.sh shell/test-case2.sh $WORKING_DIR/

RUN chmod ug+x $WORKING_DIR/*.sh

# timezone setting
RUN ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

VOLUME ["/logs001/jjobs"]

USER jjobs

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]

