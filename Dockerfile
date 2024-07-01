FROM alpine:3

# Metadata params
ARG BUILD_DATE
ARG ANSIBLE_VERSION=9.1.0
ARG ANSIBLE_LINT_VERSION=6.22.1
ARG MITOGEN_VERSION=0.3.4
ARG VCS_REF

# Metadata
LABEL maintainer="Pascal A. <pascalito@gmail.com>" \
  org.label-schema.url="https://gitlab.com/pad92/docker-ansible-alpine/blob/master/README.md" \
  org.label-schema.build-date=${BUILD_DATE} \
  org.label-schema.version=${ANSIBLE_VERSION} \
  org.label-schema.version_ansible=${ANSIBLE_VERSION} \
  org.label-schema.version_ansible_lint=${ANSIBLE_LINT_VERSION} \
  org.label-schema.vcs-url="https://gitlab.com/pad92/docker-ansible-alpine.git" \
  org.label-schema.vcs-ref=${VCS_REF} \
  org.label-schema.docker.dockerfile="/Dockerfile" \
  org.label-schema.description="Ansible on alpine docker image" \
  org.label-schema.schema-version="1.0"

RUN apk --update --no-cache add \
        ca-certificates \
        git \
        openssh-client \
        openssl \
        py3-cryptography \
        py3-pip \
        py3-yaml \
        python3\
        rsync \
        sshpass

RUN apk --update --no-cache add --virtual \
        .build-deps \
        build-base \
        cargo \
        curl \
        libffi-dev \
        openssl-dev \
        python3-dev \
  && pip3 install --no-cache-dir --upgrade \
        pip \
  && pip3 install --no-cache-dir --upgrade --no-binary \
        cffi \
        ansible==${ANSIBLE_VERSION} \
        ansible-lint==${ANSIBLE_LINT_VERSION} \
        mitogen==${MITOGEN_VERSION} \
  && apk del \
          .build-deps \
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
