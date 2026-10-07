# Docker-Ansible base image

![Pipeline](https://gitlab.com/pad92/docker-ansible-alpine/badges/master/pipeline.svg)
![version](https://img.shields.io/docker/v/pad92/ansible-alpine?sort=semver)
[![Docker Pulls](https://img.shields.io/docker/pulls/pad92/ansible-alpine)](https://hub.docker.com/r/pad92/ansible-alpine/)
![Docker Image Size](https://img.shields.io/docker/image-size/pad92/ansible-alpine/latest)
![Docker Stars](https://img.shields.io/docker/stars/pad92/ansible-alpine)
## Usage

### Environment variables

| Variable             | Default Value    | Usage                                       |
|----------------------|------------------|---------------------------------------------|
| PIP_REQUIREMENTS     | requirements.txt | Install Python package requirements         |
| ANSIBLE_REQUIREMENTS | requirements.yml | Install Ansible Galaxy requirements          |
| DEPLOY_KEY           |                  | Provide an SSH private key to the container  |
| CA_CERT_UPGRADE      |                  | Set to `true` to update ca-certificates      |

### Mitogen

To enable mitogen, add this configuration into defaults in ansible.cfg file (adjust the Python version path if using a custom Alpine base):

```cfg
[defaults]
strategy_plugins = /usr/lib/python3.14/site-packages/ansible_mitogen/plugins/strategy
strategy = mitogen_linear
```

Full documentation: https://mitogen.networkgenomics.com/ansible_detailed.html

### Run Playbook

```sh
docker run -it --rm \
  -v "${PWD}:/ansible" \
  pad92/ansible-alpine:latest \
  ansible-playbook -i inventory playbook.yml
```

### Generate Base Role structure

```sh
docker run -it --rm \
  -v "${PWD}:/ansible" \
  pad92/ansible-alpine:latest \
  ansible-galaxy init role-name
```

### Lint Role

```sh
docker run -it --rm \
  -v "${PWD}:/ansible" \
  pad92/ansible-alpine:latest \
  ansible-lint tests/playbook.yml
```

### Run with forwarding ssh agent

```sh
docker run -it --rm \
  -v "$(readlink -f "$SSH_AUTH_SOCK"):/ssh-agent" \
  -v "${PWD}:/ansible" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  pad92/ansible-alpine:latest \
  sh
```

### Add custom CA certificates

```sh
docker run -it --rm \
  -v "$(readlink -f "$SSH_AUTH_SOCK"):/ssh-agent" \
  -v "${PWD}:/ansible" \
  -v "${PWD}/ca-certificates:/usr/local/share/ca-certificates" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  pad92/ansible-alpine:latest sh
```


## Local Development and Testing

A `Makefile` is provided to build and run the test suite locally, matching the steps and variables configured in `.gitlab-ci.yml`.

### Version control

Image versions live in `versions.env`. Both `make build` and the CI pipeline read that file. A direct Docker build needs the same version arguments:

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

The scheduled GitLab job checks PyPI for a newer Ansible release. If one is available, it opens a merge request that updates `versions.env` and `CHANGELOG.md`. The regular build and security jobs then run for the merge request.

Create a daily or weekly pipeline schedule on the default branch. Add a masked project variable named `GITLAB_API_TOKEN` with permission to read the repository, create branches and commits, and open merge requests through the GitLab API.

### Manual build for an Ansible version

To build a specific Ansible version without changing `versions.env`, start a pipeline from **Run pipeline**. The form pre-fills `MANUAL_ANSIBLE_VERSION` with `13.7.0`. Leave `MANUAL_ANSIBLE_CORE_VERSION` empty to resolve a compatible core version automatically, or set it to pin one yourself.

The job publishes the image as `ansible-<version>-<commit>`, for example `ansible-13.7.0-abc12345`. Set `MANUAL_IMAGE_TAG` to choose a different tag.

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
