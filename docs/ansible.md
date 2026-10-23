# Using the Ansible image

The `pad92/ansible-alpine` image provides Ansible, Ansible Lint, and Mitogen
in an Alpine-based container. Mount your project at `/ansible` and run Ansible
commands from that directory. The examples below use the floating `latest` tag;
pin a version or digest when you need a reproducible environment.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `PIP_REQUIREMENTS` | `requirements.txt` | Path to the pip requirements file. |
| `ANSIBLE_REQUIREMENTS` | `requirements.yml` | Path to the Ansible Galaxy requirements file. |
| `DEPLOY_KEY` | unset | Provide an SSH private key to the container. |
| `CA_CERT_UPGRADE` | unset | Set to `true` to upgrade the `ca-certificates` package at startup. |

The requirements files are read from the container's working directory, which
is `/ansible` in these examples. If a requirements file exists, the entrypoint
installs it before running the requested command. An unset or empty variable
uses the default filename shown above; point it to a file that does not exist
to skip that installation.

## Run a playbook

Mount the current directory at `/ansible`; Ansible then sees the inventory and
playbook at the paths passed on the command line:

```sh
docker run --rm -it \
  -v "${PWD}:/ansible" \
  pad92/ansible-alpine:latest \
  ansible-playbook -i inventory playbook.yml
```

The image sets `/ansible` as its working directory. Add other mounts, such as
SSH configuration or cloud credentials, only when the playbook needs them.

## Create and lint a role

Create a role skeleton in the mounted project:

```sh
docker run --rm -it \
  -v "${PWD}:/ansible" \
  pad92/ansible-alpine:latest \
  ansible-galaxy init role-name
```

Run Ansible Lint against a playbook using the same image:

```sh
docker run --rm -it \
  -v "${PWD}:/ansible" \
  pad92/ansible-alpine:latest \
  ansible-lint tests/playbook.yml
```

## Forward the host SSH agent

When a playbook connects to hosts using keys held by the host's SSH agent, mount
the agent socket and point `SSH_AUTH_SOCK` at its container path:

```sh
docker run --rm -it \
  -v "$(readlink -f "$SSH_AUTH_SOCK"):/ssh-agent" \
  -v "${PWD}:/ansible" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  pad92/ansible-alpine:latest \
  ansible-playbook -i inventory playbook.yml
```

This passes access to the agent socket; the private key itself remains on the
host. The host must have `SSH_AUTH_SOCK` set and `readlink` available.

## Use custom CA certificates

Place PEM certificates with the `.crt` extension in a project directory such
as `ca-certificates/`, then mount it at the system's local certificate
directory. The image entrypoint installs the mounted certificates before
network-dependent setup:

```sh
docker run --rm -it \
  -v "${PWD}:/ansible" \
  -v "${PWD}/ca-certificates:/usr/local/share/ca-certificates:ro" \
  pad92/ansible-alpine:latest \
  ansible-playbook -i inventory playbook.yml
```

Set `CA_CERT_UPGRADE=true` when the container also needs to upgrade the
`ca-certificates` package at startup:

```sh
docker run --rm -it \
  -v "${PWD}:/ansible" \
  -v "${PWD}/ca-certificates:/usr/local/share/ca-certificates:ro" \
  -e CA_CERT_UPGRADE=true \
  pad92/ansible-alpine:latest \
  ansible-playbook -i inventory playbook.yml
```

## Enable Mitogen

Add the following to the `[defaults]` section of `ansible.cfg`. The plugin
directory includes the Python version used by the image; adjust it if you use
a custom base image or a different Python version.

```ini
[defaults]
strategy_plugins = /usr/lib/python3.14/site-packages/ansible_mitogen/plugins/strategy
strategy = mitogen_linear
```

See the [Mitogen Ansible guide](https://mitogen.networkgenomics.com/ansible_detailed.html)
for strategy configuration and usage details.
