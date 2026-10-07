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
| CA_CERT_UPGRADE      |                  | set to `true` to update ca-certificates package |

### Mitogen

To enable mitogen, add this configuration into defaults in ansible.cfg file (adjust the Python version path if using a custom Alpine base):

```cfg
[defaults]
strategy_plugins = /usr/lib/python3.14/site-packages/ansible_mitogen/plugins/strategy
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

### Add custom CA certificates

```sh
docker run -it --rm \
  -v $(readlink -f $SSH_AUTH_SOCK):/ssh-agent \
  -v ${PWD}:/ansible \
  -v ${PWD}/ca-certificates:/usr/local/share/ca-certificates \
  -e SSH_AUTH_SOCK=/ssh-agent \
  pad92/ansible-alpine:latest sh
```


## Local Development and Testing

A `Makefile` is provided to build and run the test suite locally, matching the steps and variables configured in `.gitlab-ci.yml`.

### Version control

The image versions are defined in `versions.env`. `make build` and the CI pipeline use that file directly. The Dockerfile requires the version arguments, so a direct Docker build must pass the same values explicitly:

```sh
. ./versions.env
docker build \
  --build-arg ALPINE_IMAGE="${ALPINE_IMAGE}" \
  --build-arg ANSIBLE_VERSION="${ANSIBLE_VERSION}" \
  --build-arg ANSIBLE_CORE_VERSION="${ANSIBLE_CORE_VERSION}" \
  --build-arg ANSIBLE_LINT_VERSION="${ANSIBLE_LINT_VERSION}" \
  --build-arg MITOGEN_VERSION="${MITOGEN_VERSION}" \
  .
```

### Automatic Ansible updates

The project includes a scheduled GitLab job that checks PyPI for a newer Ansible release. When it finds one, it creates a branch and a Merge Request that updates `versions.env` and `CHANGELOG.md`. The usual build, version check, and security tests then run on that Merge Request.

Create a daily or weekly pipeline schedule on the default branch and add a masked project variable named `GITLAB_API_TOKEN`. The token needs permission to read the repository and create branches, commits, and Merge Requests through the GitLab API.

### Build manuel d'une version

Pour construire ponctuellement une version précise sans modifier `versions.env`, lance une pipeline depuis **Run pipeline**. Le job `build_manual_ansible` propose déjà `MANUAL_ANSIBLE_VERSION=13.7.0` et `MANUAL_ANSIBLE_CORE_VERSION=2.20.9` ; ces valeurs restent modifiables avant de démarrer le job.

La pipeline récupère automatiquement une version compatible d'`ansible-core` et publie l'image sous un tag de la forme `ansible-13.7.0-<commit>`. Tu peux imposer une version avec `MANUAL_ANSIBLE_CORE_VERSION` ou choisir le tag avec `MANUAL_IMAGE_TAG`.

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
