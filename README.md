# Docker-Ansible base image

[![Layers](https://images.microbadger.com/badges/image/pad92/ansible-alpine.svg)](https://microbadger.com/images/pad92/ansible-alpine) [![GitHub issues](https://img.shields.io/github/issues/pad92/docker-ansible-alpine.svg)](https://github.com/pad92/docker-ansible-alpine) [![Docker Automated build](https://img.shields.io/docker/automated/pad92/ansible-alpine.svg?maxAge=2592000)](https://hub.docker.com/r/pad92/ansible-alpine/) [![Docker Build Status](https://img.shields.io/docker/build/pad92/ansible-alpine.svg?maxAge=2592000)](https://hub.docker.com/r/pad92/ansible-alpine/) [![Docker Pulls](https://img.shields.io/docker/pulls/pad92/ansible-alpine.svg)](https://hub.docker.com/r/pad92/ansible-alpine/)

## Usage

### Environnement variable

| Variable             | Default Value    | Usage                                           |
|----------------------|------------------|-------------------------------------------------|
| PIP_REQUIREMENTS     | requirements.txt | install python library requirements             |
| ANSIBLE_REQUIREMENTS | requirements.yml | install ansible galaxy roles requirements       |
| DEPLOY_KEY           |                  | pass an SSH private key to use in container     |
| CA_CERT_UPGRADE      |                  | set to `true` to update ca-certificates package |

### Mitogen

To enable mitogen, add this configuration into defaults in defaults.cfg file
```
action_plugins = ~/.ansible/plugins/action:/usr/share/ansible/plugins/action
strategy_plugins = /opt/mitogen/ansible_mitogen/plugins/strategy
strategy = mitogen_linear
```

### Run Playbook

```sh
docker run -it --rm \
  -v ${PWD}:/ansible \
  pad92/ansible-alpine:latest \
  ansible-playbook -i inventory playbook.yml
```

### Generate Base Role structure

```sh
docker run -it --rm \
  -v ${PWD}:/ansible \
  pad92/ansible-alpine:latest \
  ansible-galaxy init role-name
```

### Lint Role

```sh
docker run -it --rm pad92/ansible-alpine:latest \
  -v ${PWD}:/ansible ansible-playbook tests/playbook.yml --syntax-check
```

### Run with forwarding ssh agent

```sh
docker run -it --rm \
  -v $(readlink -f $SSH_AUTH_SOCK):/ssh-agent \
  -v ${PWD}:/ansible \
  -e SSH_AUTH_SOCK=/ssh-agent \
  pad92/ansible-alpine:latest \
  sh
```

### add custom certifitates

```sh
docker run -it --rm \
  -v $(readlink -f $SSH_AUTH_SOCK):/ssh-agent \
  -v ${PWD}:/ansible \
  -v ${PWD}/ca-certificates:/usr/local/share/ca-certificates
  -e SSH_AUTH_SOCK=/ssh-agent \
  pad92/ansible-alpine:2.10.7-1 sh
```
