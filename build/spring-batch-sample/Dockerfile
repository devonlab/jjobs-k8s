# J-Jobs 
#
# Copyright (c) LG CNS and/or its affiliates. All rights reserved.

# Pull base image
# ---------------
#FROM amazonlinux:2023 as base
FROM amazoncorretto:8-al2023

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
RUN dnf update -y && dnf clean all


# Copy files needed during both installation and runtime
# -------------
COPY shell/entrypoint.sh /entrypoint.sh
COPY shell/test-case1.sh shell/test-case2.sh $WORKING_DIR/
COPY shell/springbatch-sample-1.0.0.jar shell/spring-batch-sample.sh $WORKING_DIR/
RUN chmod ug+x $WORKING_DIR/*.sh

# timezone setting
RUN ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime

VOLUME ["/logs001/jjobs"]

EXPOSE 22
ENTRYPOINT ["/working/spring-batch-sample.sh", "-fileName=not-exist-file.csv"]


