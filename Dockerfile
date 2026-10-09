ARG ALPINE_IMAGE=alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
FROM ${ALPINE_IMAGE}

# Metadata params
ARG BUILD_DATE
ARG ANSIBLE_VERSION
ARG ANSIBLE_CORE_VERSION
ARG ANSIBLE_LINT_VERSION
ARG MITOGEN_VERSION
ARG BUILD_VCSREF

# Metadata
LABEL org.opencontainers.image.authors="Pascal A. <pascalito@gmail.com>" \
      org.opencontainers.image.url="https://gitlab.com/pad92/docker-ansible-alpine" \
      org.opencontainers.image.documentation="https://gitlab.com/pad92/docker-ansible-alpine/blob/master/README.md" \
      org.opencontainers.image.source="https://gitlab.com/pad92/docker-ansible-alpine.git" \
      org.opencontainers.image.version=${ANSIBLE_VERSION} \
      org.opencontainers.image.revision=${BUILD_VCSREF} \
      org.opencontainers.image.created=${BUILD_DATE} \
      org.opencontainers.image.title="docker-ansible-alpine" \
      org.opencontainers.image.description="Ansible on Alpine Docker image" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}"

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
        sshpass \
  && apk add --no-cache --virtual .build-deps \
        build-base \
        libffi-dev \
        openssl-dev \
        python3-dev \
  && python3 -m venv --system-site-packages "${VIRTUAL_ENV}" \
  && test -n "${ANSIBLE_VERSION}" \
  && test -n "${ANSIBLE_CORE_VERSION}" \
  && test -n "${ANSIBLE_LINT_VERSION}" \
  && test -n "${MITOGEN_VERSION}" \
  && pip3 install --no-cache-dir --no-compile \
        ansible==${ANSIBLE_VERSION} \
        ansible-core==${ANSIBLE_CORE_VERSION} \
        ansible-lint==${ANSIBLE_LINT_VERSION} \
        mitogen==${MITOGEN_VERSION} \
        'msgpack>=1.2.1' \
        'setuptools>=78.1.1' \
        'urllib3>=2.8.0' \
  && apk del .build-deps py3-cryptography py3-pip \
  && pip3 --version \
  && rm -rf /var/cache/apk/* \
  && find /usr/lib/ "${VIRTUAL_ENV}/lib" -type d -name '__pycache__' -prune -print0 | xargs -0 rm -rf \
  && find /usr/lib/ "${VIRTUAL_ENV}/lib" -type f -name '*.py[co]' -print0 | xargs -0 rm -f \
  && find "${VIRTUAL_ENV}/lib" -path '*/pip/_vendor/bom.cdx.json' -delete

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
