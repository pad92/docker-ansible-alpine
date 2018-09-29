# Docker-Ansible base image

[![Layers](https://images.microbadger.com/badges/image/pad92/ansible-alpine.svg)](https://microbadger.com/images/pad92/ansible-alpine) [![GitHub issues](https://img.shields.io/github/issues/pad92/docker-ansible-alpine.svg)](https://github.com/pad92/docker-ansible-alpine) [![Docker Automated build](https://img.shields.io/docker/automated/pad92/ansible-alpine.svg?maxAge=2592000)](https://hub.docker.com/r/pad92/ansible-alpine/) [![Docker Build Status](https://img.shields.io/docker/build/pad92/ansible-alpine.svg?maxAge=2592000)](https://hub.docker.com/r/pad92/ansible-alpine/) [![Docker Pulls](https://img.shields.io/docker/pulls/pad92/ansible-alpine.svg)](https://hub.docker.com/r/pad92/ansible-alpine/)
[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bgithub.com%2Fpad92%2Fdocker-ansible-alpine.svg?type=shield)](https://app.fossa.io/projects/git%2Bgithub.com%2Fpad92%2Fdocker-ansible-alpine?ref=badge_shield)

## Usage

### Environnement variable

| Variable             | Default Value    | Usage                                       |
|----------------------|------------------|---------------------------------------------|
| PIP_REQUIREMENTS     | requirements.txt | install python library requirements         |
| ANSIBLE_REQUIREMENTS | requirements.yml | install ansible galaxy roles requirements   |
| DEPLOY_KEY           |                  | pass an SSH private key to use in container |

### Run Playbook

```
docker run -it --rm \
  -v ${PWD}:/ansible \
  pad92/ansible-alpine:latest \
  ansible-playbook -i inventory playbook.yml
```

### Generate Base Role structure

```
docker run -it --rm \
  -v ${PWD}:/ansible \
  pad92/ansible-alpine:latest \
  ansible-galaxy init role-name
```

### Lint Role

```
docker run -it --rm pad92/ansible-alpine:latest \
  -v ${PWD}:/ansible ansible-playbook tests/playbook.yml --syntax-check
```
### Run with forwarding ssh agent

```
docker run -it --rm \
  -v $(readlink -f $SSH_AUTH_SOCK):/ssh-agent \
  -v ${PWD}:/ansible \
  -e SSH_AUTH_SOCK=/ssh-agent \
  pad92/ansible-alpine:latest \
  sh
```



## License
[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bgithub.com%2Fpad92%2Fdocker-ansible-alpine.svg?type=large)](https://app.fossa.io/projects/git%2Bgithub.com%2Fpad92%2Fdocker-ansible-alpine?ref=badge_large)