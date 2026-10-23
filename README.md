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

### Automatic dependency updates

Create a daily or weekly GitLab pipeline schedule on the default branch. Add a
masked project variable named `GITLAB_API_TOKEN` with permission to read the
repository, create branches and commits, and open merge requests through the
GitLab API.

The schedule checks PyPI for newer Ansible releases, GitHub and Docker Hub for
Trivy, and Docker Hub for Alpine updates within the configured branch (for
example, `3.24.x`). Alpine checks both
the version and the multi-platform digest, including rebuilds of the same patch
release. Each update opens a merge request with a changelog entry. Alpine updates
keep `versions.env`, the Dockerfile default, and CI image references aligned.
Existing update MRs are left for review; they are not merged automatically.
A switch to another Alpine branch requires a separate change.

When a branch already has an open MR, GitLab runs the MR pipeline and skips
the duplicate branch push pipeline. This keeps each commit to one image build.

The schedule also resolves the published GitLab `latest` tag to a digest and
scans its AMD64 and ARM64 images for HIGH and CRITICAL findings. This detects
newly reported vulnerabilities without rebuilding or publishing an image.
A failed scheduled scan needs investigation even when no upstream update is
available. The scan requires an existing `latest` image.

### Image revisions and publication

After a merge to the default branch, CI builds a candidate named
`ci-<pipeline-id>-<job-id>`. Build metadata passes its digest to the functional
checks and the AMD64/ARM64 Trivy scans. Release verifies that all checks recorded
that same digest, then publishes it without rebuilding.

Each distinct validated image receives the next revision for its Ansible version:
`14.5.0-1`, `14.5.0-2`, and so on. This includes Alpine security fixes and other
image changes. A new Ansible version starts at `-1`. GitLab is the revision
ledger; Docker Hub receives the same numbered tag when its credentials are
configured. A retry with the same digest reuses its revision, including after a
partial publication.

The `14.5.0` alias follows the latest published revision for that Ansible version.
The `latest` alias follows it when Ansible is equal to or newer than its current
version. A backport for an older Ansible version does not move `latest` backwards.
Release jobs share a lock and reject obsolete commits or older pipeline retries.

Keep numbered tags in both registries: exclude tags matching
`[0-9]+\.[0-9]+\.[0-9]+-[0-9]+` from cleanup policies. Deleting these tags breaks
the revision ledger. For exact deployments and rollbacks, use the published
image digest. Do not write stable aliases or numbered revisions outside the
release job; restrict their modification to CI credentials where the registry
supports it.

Git tag pipelines publish `git-<git-tag>`, and branch pipelines publish
`branch-<branch-slug>`. These namespaces cannot replace `latest`, Ansible aliases,
or numbered revisions. Registry protection and retention settings must be
configured separately; this repository does not modify them.

### Local CI commands

The Makefile exposes the same update and release scripts as GitLab:

```sh
make test-ci                # Script checks and simulated tests; no image build
make check-ansible-release  # Report available Ansible updates
make check-alpine-release   # Report available Alpine updates
make check-trivy-release    # Report available Trivy updates
make check-updates          # Run both update checks
make scan-published        # Scan the published latest digest on AMD64 and ARM64
```

`make test-ci` requires Python 3 with PyYAML, jq, ShellCheck, Git, and Make.
It is also included in `make test` and used by the GitLab validation job.
The local update commands require curl and jq; Alpine detection also requires
Docker Buildx. They compare upstream versions against the local `versions.env`
and report available updates. No GitLab configuration or token is needed, and
they do not change files or create merge requests.

The scheduled CI jobs keep their default MR creation mode and still require
`CI_API_V4_URL`, `CI_PROJECT_ID`, `CI_DEFAULT_BRANCH`, and `GITLAB_API_TOKEN`.
The Makefile selects the read-only mode explicitly with `--check`.

`make scan-published` resolves `latest` once and scans that digest without
building an image. It requires Docker and registry access. For a private
registry, provide `CI_REGISTRY_USER` and `CI_JOB_TOKEN`; the scan uses them as
Trivy credentials unless `TRIVY_USERNAME` and `TRIVY_PASSWORD` are set explicitly.
`CI_REGISTRY_IMAGE` selects the repository, and `SCAN_PLATFORMS` can restrict the
scan (for example, `SCAN_PLATFORMS=linux/arm64`).

`make release` is used by the GitLab `release_master` job. It requires its CI
context, tested-image artifacts, and release lock, so it refuses ordinary local
execution. Start publication through the normal GitLab pipeline.

### Manual build for an Ansible version

To build a specific Ansible version without changing `versions.env`, start a pipeline from **Run pipeline**. The form pre-fills `MANUAL_ANSIBLE_VERSION` with `13.7.0`. Leave `MANUAL_ANSIBLE_CORE_VERSION` empty to resolve a compatible core version automatically, or set it to pin one yourself.

The job publishes the image as `manual-<version>-<commit>`, for example `manual-13.7.0-abc12345`. `MANUAL_IMAGE_TAG` changes the suffix after `manual-`; it cannot select a stable tag. Manual builds do not update `latest` and do not run the regular image tests.

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

Trivy checks HIGH and CRITICAL findings in one scan and returns a nonzero exit
code when it finds either. Secret scanning remains enabled.

If Trivy logs `Unable to get vulnerability details (CVE may be rejected)`, its
database references a CVE without a corresponding details record. On 2026-10-23,
this occurred for `CVE-2026-107891` with Trivy 0.76.1, including after downloading
a fresh database. The scan completed with exit code 0 and no HIGH or CRITICAL
findings, but the missing CVE details remain an upstream data limitation.
Updating the scanner or clearing the local cache did not resolve this warning.
Rebuilding with Alpine 3.24.3 removed the affected musl
version and this warning in the local scan. Do not add a CVE ignore rule or
disable scanning to hide it.

### Cleanup
To remove the local Trivy cache database and clean up buildx configurations:
```sh
make clean
```
