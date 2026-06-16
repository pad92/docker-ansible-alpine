# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [13.7.0] - 2026-06-16

### Changed
- Upgraded base image **Alpine** to `3.24`.
- Upgraded **Ansible** to `13.7.0` (required for Python 3.14 compatibility on Alpine 3.24).
- Upgraded **Ansible-Lint** to `26.4.0`.

---

## [12.2.0] - 2026-06-16

### Changed
- Upgraded base image **Alpine** to `3.22` (keeps Python 3.12 compatibility).
- Upgraded **Ansible** to `12.2.0` (resolves community.general Keycloak credential leak vulnerability CVE-2025-14010).

---

## [11.13.0] - 2026-06-16

### Added
- **Alpine 3.20 base image support** (ships with Python 3.12).
- **PEP 668 compliance** via `ENV PIP_BREAK_SYSTEM_PACKAGES=1` allowing global pip installations inside the container.
- **Dedicated CI test phase** (`test` stage) running automated checks (`ansible --version`, `ansible-lint --version`, and Mitogen import checks) on all build jobs in `.gitlab-ci.yml`.
- **Dynamic Alpine builds**: Added top-level `ARG ALPINE_VERSION=3.20` in `Dockerfile` and propagated it to GitLab CI and build scripts.
- **OCI compliance labels** (`org.opencontainers.image.*`) replacing the obsolete schema v1 labels.

### Changed
- Upgraded default **Ansible** to `11.13.0` (uses `ansible-core` 2.18).
- Upgraded default **Ansible-Lint** to `25.12.0`.
- Upgraded default **Mitogen** to `0.3.49` for native Ansible 11 compatibility.
- Updated Mitogen configuration examples in `README.md` to target Python 3.12 directory structures.
- Removed obsolete `linux/arm/v7` architecture from build hooks and GitLab CI tagging jobs.

### Fixed
- Fixed Docker parameter ordering syntax bugs in `README.md` linter and syntax check examples (volume mount `-v` parameters moved before the image tag).
- Pinned `hooks/build_2.10` to Alpine `3.18` and Mitogen `0.3.4` to ensure Ansible 2.10 compatibility is preserved on older Python environments.

### Optimized
- Optimized image build time: pre-installed `py3-cffi` and `py3-ruamel.yaml` via Alpine's package manager, allowing the removal of heavy compilers like `cargo` and dependencies like `curl` from build-time dependencies (`.build-deps`).

---

## [9.0.1] - 2023-11-25

### Added
- Restored **Mitogen** strategy support (version `0.3.4`).
- Added support for building legacy Ansible 2.10.7 in hooks.

### Changed
- Upgraded default **Ansible** to `9.0.1`.
- Upgraded default **Ansible-Lint** to `6.22.0`.

### Fixed
- Fixed strategy plugins path in `README.md`.

---

## [8.5.0] - 2023-10-16

### Added
- Multi-architecture platform builds (`linux/arm64`, `linux/amd64`, and `linux/arm/v7`).
- Security fixes and CI optimization.

### Changed
- Upgraded default **Ansible** to `8.5.0`.
- Upgraded default **Ansible-Lint** to `6.20.3`.
