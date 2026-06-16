ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

# Metadata params
ARG BUILD_DATE
ARG ANSIBLE_VERSION=12.2.0
ARG ANSIBLE_LINT_VERSION=25.12.0
ARG MITOGEN_VERSION=0.3.49
ARG VCS_REF

# Metadata
LABEL org.opencontainers.image.authors="Pascal A. <pascalito@gmail.com>" \
      org.opencontainers.image.url="https://gitlab.com/pad92/docker-ansible-alpine" \
      org.opencontainers.image.documentation="https://gitlab.com/pad92/docker-ansible-alpine/blob/master/README.md" \
      org.opencontainers.image.source="https://gitlab.com/pad92/docker-ansible-alpine.git" \
      org.opencontainers.image.version=${ANSIBLE_VERSION} \
      org.opencontainers.image.revision=${VCS_REF} \
      org.opencontainers.image.created=${BUILD_DATE} \
      org.opencontainers.image.title="docker-ansible-alpine" \
      org.opencontainers.image.description="Ansible on Alpine Docker image" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

# PEP 668 compatibility (allows installing pip packages globally on Alpine 3.20+)
ENV PIP_BREAK_SYSTEM_PACKAGES=1

RUN apk add --no-cache \
        ca-certificates \
        git \
        openssh-client \
        openssl \
        py3-cffi \
        py3-cryptography \
        py3-pip \
        py3-ruamel.yaml \
        py3-yaml \
        python3 \
        rsync \
        sshpass

RUN apk add --no-cache --virtual .build-deps \
        build-base \
        libffi-dev \
        openssl-dev \
        python3-dev \
  && pip3 install --no-cache-dir \
        ansible==${ANSIBLE_VERSION} \
        ansible-lint==${ANSIBLE_LINT_VERSION} \
        mitogen==${MITOGEN_VERSION} \
  && apk del .build-deps \
  && rm -rf /var/cache/apk/* \
  && find /usr/lib/ -name '__pycache__' -print0 | xargs -0 -n1 rm -rf \
  && find /usr/lib/ -name '*.pyc' -print0 | xargs -0 -n1 rm -rf

RUN mkdir -p /etc/ansible \
  && echo 'localhost' > /etc/ansible/hosts \
  && echo -e """\
\n\
Host *\n\
    StrictHostKeyChecking no\n\
    UserKnownHostsFile=/dev/null\n\
""" >> /etc/ssh/ssh_config

COPY entrypoint /usr/local/bin/

WORKDIR /ansible

ENTRYPOINT ["entrypoint"]

# default command: display Ansible version
CMD [ "ansible-playbook", "--version" ]

