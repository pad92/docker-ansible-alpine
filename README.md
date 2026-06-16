> [!WARNING]  
> moved to https://github.com/Cloud-Temple/docker-ansible-alpine

# Docker-Ansible base image

![Pipeline](https://gitlab.com/pad92/docker-ansible-alpine/badges/master/pipeline.svg)
![version](https://img.shields.io/docker/v/pad92/ansible-alpine?sort=semver)
[![Docker Pulls](https://img.shields.io/docker/pulls/pad92/ansible-alpine)](https://hub.docker.com/r/pad92/ansible-alpine/)
![Docker Image Size](https://img.shields.io/docker/image-size/pad92/ansible-alpine/latest)
![Docker Stars](https://img.shields.io/docker/stars/pad92/ansible-alpine)
## Usage

### Environnement variable

| Variable             | Default Value    | Usage                                       |
|----------------------|------------------|---------------------------------------------|
| PIP_REQUIREMENTS     | requirements.txt | install python library requirements         |
| ANSIBLE_REQUIREMENTS | requirements.yml | install ansible galaxy roles requirements   |
| DEPLOY_KEY           |                  | pass an SSH private key to use in container |

### Mitogen

To enable mitogen, add this configuration into defaults in ansible.cfg file (adjust the Python version path if using a custom Alpine base):

```cfg
[defaults]
strategy_plugins = /usr/lib/python3.12/site-packages/ansible_mitogen/plugins/strategy
strategy = mitogen_linear
```

Full documentation : https://mitogen.networkgenomics.com/ansible_detailed.html

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
docker run -it --rm \
  -v ${PWD}:/ansible \
  pad92/ansible-alpine:latest \
  ansible-lint tests/playbook.yml
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

## Local Development and Testing

A `Makefile` is provided to build and run the test suite locally, matching the steps and variables configured in `.gitlab-ci.yml`.

### Build the Image
To build the Docker image locally and load it directly into your local Docker daemon storage (no registry push):
```sh
make build
```

### Run All Tests
To run all tests (Ansible functional checks, Mitogen imports, and Trivy security scans):
```sh
make test
```
*Note: The Trivy scan mounts your host's `/var/run/docker.sock` to scan the locally built image without pulling it, and persists its database to `./trivy-cache`.*

### Run Specific Test Targets
You can also run specific test jobs individually:
```sh
make test-ansible    # Run ansible and ansible-lint checks
make test-mitogen    # Run mitogen import verification
make test-trivy      # Run Trivy vulnerability scan
```

### Cleanup
To remove the local Trivy cache database and clean up buildx configurations:
```sh
make clean
```
