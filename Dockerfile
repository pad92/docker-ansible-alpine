FROM alpine:3.17

# Metadata params
ARG BUILD_DATE
ARG ANSIBLE_VERSION
ARG ANSIBLE_LINT_VERSION
ARG MITOGEN_VERSION
ARG VCS_REF

# Metadata
LABEL maintainer="Pascal A. <pascalito@gmail.com>" \
      org.label-schema.url="https://github.com/pad92/docker-ansible-alpine/blob/master/README.md" \
      org.label-schema.build-date=${BUILD_DATE} \
      org.label-schema.version=${ANSIBLE_VERSION} \
      org.label-schema.version_ansible=${ANSIBLE_VERSION} \
      org.label-schema.version_ansible_lint=${ANSIBLE_LINT_VERSION} \
      org.label-schema.version_mitogen=${MITOGEN_VERSION} \
      org.label-schema.vcs-url="https://github.com/pad92/docker-ansible-alpine.git" \
      org.label-schema.vcs-ref=${VCS_REF} \
      org.label-schema.docker.dockerfile="/Dockerfile" \
      org.label-schema.description="Ansible on alpine docker image" \
      org.label-schema.schema-version="1.0"

RUN apk --update --no-cache add \
        ca-certificates \
        git \
        openssh-client \
        openssl \
        python3\
        py3-pip \
        py3-cryptography \
        rsync \
        sshpass

RUN apk --update add --virtual \
        .build-deps \
        python3-dev \
        libffi-dev \
        openssl-dev \
        build-base \
        curl \
 && if [ ! -z "${MITOGEN_VERSION+x}" ]; then curl -s -L https://github.com/mitogen-hq/mitogen/archive/refs/tags/v${MITOGEN_VERSION}.tar.gz | tar xzf - -C /opt/ \
 && mv /opt/mitogen-* /opt/mitogen; fi \
 && pip3 install --upgrade \
        pip \
        cffi \
 && pip3 install \
        ansible==${ANSIBLE_VERSION} \
        ansible-lint==${ANSIBLE_LINT_VERSION} \
 && apk del \
        .build-deps \
 && rm -rf /var/cache/apk/*

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
