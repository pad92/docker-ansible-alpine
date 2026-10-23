"""Exercise release and update scripts with isolated registries and GitLab APIs."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIGEST = "sha256:" + "a" * 64
OLD = "sha256:" + "b" * 64
NEW = "sha256:" + "c" * 64
REGISTRY = "registry.invalid/project"
HUB = "hub.invalid/project"
SHA = "d" * 40


def labels(version: str = "14.5.0", pipeline: str = "20") -> dict[str, str]:
    return {
        "org.opencontainers.image.version": version,
        "org.opencontainers.image.revision": SHA,
        "io.gitlab.ci.pipeline.id": pipeline,
    }


class ScriptsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        shutil.copytree(ROOT / "ci", self.work / "ci")
        shutil.copy(ROOT / "versions.env", self.work)
        bin_dir = self.work / "bin"
        bin_dir.mkdir()
        for name in ("docker", "curl", "git"):
            target = bin_dir / name
            shutil.copy(ROOT / "ci/tests/fake_tools.py", target)
            target.chmod(0o755)
        self.state_path = self.work / "state.json"
        self.state = {
            "head": SHA,
            "tags": {},
            "labels": {DIGEST: labels(), OLD: labels(pipeline="19")},
            "files": {
                name: (ROOT / name).read_text()
                for name in (
                    "versions.env",
                    "CHANGELOG.md",
                    "Dockerfile",
                    ".gitlab-ci.yml",
                )
            },
        }
        self.env = {
            **os.environ,
            "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
            "CI_TEST_STATE": str(self.state_path),
            "CI_REGISTRY_IMAGE": REGISTRY,
            "CI_COMMIT_SHA": SHA,
            "CI_DEFAULT_BRANCH": "master",
            "CI_PIPELINE_ID": "20",
            "TESTED_IMAGE": REGISTRY + "@" + DIGEST,
            "DOCKER_HUB_USER": "test",
            "DOCKER_HUB_PASSWORD": "test",
            "DU_REGISTRY_IMAGE": HUB,
            "CI_API_V4_URL": "https://gitlab.invalid/api/v4",
            "CI_PROJECT_ID": "1",
            "GITLAB_API_TOKEN": "test",
        }
        # Fixed fixtures remain valid when automated MRs update repository pins.
        versions = (
            "ALPINE_IMAGE=alpine:3.24.3@"
            + OLD
            + "\nANSIBLE_VERSION=14.5.0\nANSIBLE_CORE_VERSION=2.21.5\n"
        )
        (self.work / "versions.env").write_text(versions)
        self.state["files"]["versions.env"] = versions
        self.state["files"]["Dockerfile"] = (
            "ARG ALPINE_IMAGE=alpine:3.24.3@" + OLD + "\nFROM ${ALPINE_IMAGE}\n"
        )
        self.state["files"][".gitlab-ci.yml"] = "image: alpine:3.24.3@" + OLD + "\n"
        validation = self.work / "validation"
        validation.mkdir()
        for name in ("ansible", "mitogen", "trivy-amd64", "trivy-arm64"):
            (validation / f"{name}.txt").write_text(self.env["TESTED_IMAGE"] + "\n")

    def run_script(
        self, script: str, success: bool = True, args: tuple[str, ...] = ()
    ) -> subprocess.CompletedProcess[str]:
        self.state_path.write_text(json.dumps(self.state))
        result = subprocess.run(
            ["sh", "ci/" + script, *args],
            cwd=self.work,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.state = json.loads(self.state_path.read_text())
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_first_release_and_retry_use_same_revision(self) -> None:
        self.run_script("release-image.sh")
        self.run_script("release-image.sh")
        for registry in (REGISTRY, HUB):
            for tag in ("14.5.0-1", "14.5.0", "latest"):
                self.assertEqual(self.state["tags"][registry + ":" + tag], DIGEST)
            self.assertNotIn(registry + ":14.5.0-2", self.state["tags"])

    def test_security_revision_updates_latest_at_equal_ansible_version(self) -> None:
        for registry in (REGISTRY, HUB):
            for tag in ("14.5.0-1", "14.5.0", "latest"):
                self.state["tags"][registry + ":" + tag] = OLD
        self.run_script("release-image.sh")
        for registry in (REGISTRY, HUB):
            self.assertEqual(self.state["tags"][registry + ":14.5.0-1"], OLD)
            self.assertEqual(self.state["tags"][registry + ":14.5.0-2"], DIGEST)
            self.assertEqual(self.state["tags"][registry + ":latest"], DIGEST)

    def test_partial_publication_resumes_same_revision(self) -> None:
        self.state["publish_errors"] = [HUB + ":14.5.0-1"]
        self.run_script("release-image.sh", success=False)
        self.assertNotIn(REGISTRY + ":latest", self.state["tags"])
        self.state["publish_errors"] = []
        self.run_script("release-image.sh")
        self.assertEqual(self.state["tags"][HUB + ":14.5.0-1"], DIGEST)
        self.assertNotIn(REGISTRY + ":14.5.0-2", self.state["tags"])

    def test_obsolete_commit_does_not_publish(self) -> None:
        self.state["head"] = "e" * 40
        self.run_script("release-image.sh")
        self.assertFalse(self.state.get("writes"))

    def test_older_pipeline_same_commit_does_not_publish(self) -> None:
        self.state["tags"][REGISTRY + ":14.5.0"] = OLD
        self.state["labels"][OLD] = labels(pipeline="21")
        self.run_script("release-image.sh")
        self.assertFalse(self.state.get("writes"))

    def test_backport_keeps_newer_latest(self) -> None:
        for registry in (REGISTRY, HUB):
            self.state["tags"][registry + ":latest"] = OLD
        self.state["labels"][OLD] = labels(version="14.6.0")
        self.run_script("release-image.sh")
        for registry in (REGISTRY, HUB):
            self.assertEqual(self.state["tags"][registry + ":latest"], OLD)
            self.assertEqual(self.state["tags"][registry + ":14.5.0-1"], DIGEST)

    def test_registry_outage_is_not_a_missing_tag(self) -> None:
        self.state["errors"] = [REGISTRY + ":14.5.0-1"]
        self.run_script("release-image.sh", success=False)
        self.assertFalse(self.state.get("writes"))

    def test_conflicting_hub_tag_is_not_overwritten(self) -> None:
        self.state["tags"][HUB + ":14.5.0-1"] = OLD
        self.run_script("release-image.sh", success=False)
        self.assertFalse(self.state.get("writes"))

    def test_rebuilt_candidate_requires_new_test_results(self) -> None:
        (self.work / "validation/trivy-arm64.txt").write_text(REGISTRY + "@" + OLD)
        self.run_script("release-image.sh", success=False)
        self.assertFalse(self.state.get("writes"))

    def alpine(self, version: str = "3.24.4", digest: str = NEW) -> None:
        self.state["tags"]["alpine:3.24"] = digest
        self.state["alpine_index"] = {
            "manifests": [
                {
                    "platform": {"os": "linux", "architecture": arch},
                    "annotations": {"org.opencontainers.image.version": version},
                }
                for arch in ("amd64", "arm64")
            ]
        }

    def test_alpine_patch_updates_all_pins_in_one_mr(self) -> None:
        self.alpine()
        self.run_script("check-alpine-release.sh")
        for name in ("versions.env", "Dockerfile", ".gitlab-ci.yml"):
            self.assertIn("alpine:3.24.4@" + NEW, self.state["files"][name])
        writes = self.state["api_writes"]
        self.assertEqual(sum(w["url"].endswith("/merge_requests") for w in writes), 1)
        commit = next(w for w in writes if w["url"].endswith("/repository/commits"))
        payload = json.loads(commit["args"][commit["args"].index("--data") + 1])
        self.assertEqual(len(payload["actions"]), 4)

    def test_alpine_same_patch_new_digest_opens_mr(self) -> None:
        self.alpine("3.24.3")
        self.run_script("check-alpine-release.sh")
        self.assertIn(NEW, self.state["files"]["versions.env"])

    def test_alpine_unchanged_is_noop(self) -> None:
        pin = next(
            line.split("=", 1)[1]
            for line in self.state["files"]["versions.env"].splitlines()
            if line.startswith("ALPINE_IMAGE=")
        )
        self.alpine("3.24.3", pin.split("@")[1])
        self.run_script("check-alpine-release.sh")
        self.assertFalse(self.state.get("api_writes"))

    def test_alpine_no_duplicate_mr(self) -> None:
        self.alpine()
        self.state["open_mr"] = True
        self.run_script("check-alpine-release.sh")
        self.assertFalse(self.state.get("api_writes"))

    def test_alpine_rejects_series_change_or_downgrade(self) -> None:
        for version in ("3.25.0", "3.24.1"):
            with self.subTest(version=version):
                self.alpine(version)
                self.run_script("check-alpine-release.sh", success=False)
                self.assertFalse(self.state.get("api_writes"))

    def test_alpine_registry_failure_does_not_create_mr(self) -> None:
        self.alpine()
        self.state["errors"] = ["alpine:3.24"]
        self.run_script("check-alpine-release.sh", success=False)
        self.assertFalse(self.state.get("api_writes"))

    def test_local_checks_need_no_gitlab_configuration(self) -> None:
        self.alpine()
        self.state["forbid_gitlab"] = True
        for name in (
            "CI_API_V4_URL",
            "CI_PROJECT_ID",
            "CI_DEFAULT_BRANCH",
            "GITLAB_API_TOKEN",
        ):
            self.env.pop(name, None)
        before = (self.work / "versions.env").read_text()
        for script in ("check-ansible-release.sh", "check-alpine-release.sh"):
            with self.subTest(script=script):
                result = self.run_script(script, args=("--check",))
                self.assertIn(
                    "Upgrade Ansible" if "ansible" in script else "Update Alpine",
                    result.stdout,
                )
        self.assertFalse(self.state.get("api_writes"))
        self.assertEqual((self.work / "versions.env").read_text(), before)

    def test_mr_mode_still_requires_gitlab_configuration(self) -> None:
        self.env.pop("CI_API_V4_URL")
        self.run_script("check-ansible-release.sh", success=False)
        self.assertFalse(self.state.get("api_writes"))

    def test_ansible_updater_still_creates_mr(self) -> None:
        self.run_script("check-ansible-release.sh")
        self.assertIn("ANSIBLE_VERSION=14.6.0", self.state["files"]["versions.env"])
        self.assertTrue(self.state.get("api_writes"))


class PipelineConfigurationTest(unittest.TestCase):
    def test_yaml_scripts_and_digest_flow(self) -> None:
        import yaml

        class Loader(yaml.SafeLoader):
            pass

        Loader.add_constructor(
            "!reference", lambda loader, node: loader.construct_sequence(node)
        )
        config = yaml.load((ROOT / ".gitlab-ci.yml").read_text(), Loader=Loader)
        for name, job in config.items():
            if not isinstance(job, dict):
                continue
            for key in ("script", "before_script"):
                for command in job.get(key, []):
                    if isinstance(command, list):
                        continue  # GitLab !reference, checked at its source.
                    self.assertIsInstance(command, str, (name, command))
                    result = subprocess.run(
                        ["sh", "-n"],
                        input=command,
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 0, (name, result.stderr))
        self.assertEqual(
            config["release_master"]["resource_group"], "ansible-latest-release"
        )
        self.assertIn("TESTED_IMAGE", "\n".join(config["build_image"]["script"][1:]))
        self.assertEqual(config["scan_published"]["needs"], ["resolve_published"])
        self.assertEqual(
            config["test_trivy"]["parallel"]["matrix"][0]["SCAN_PLATFORM"],
            ["linux/amd64", "linux/arm64"],
        )
        for job in ("test_ansible", "test_mitogen", "test_trivy"):
            self.assertIn("$TESTED_IMAGE", "\n".join(config[job]["script"]))
        self.assertIn("git-", config["release_tag"]["variables"]["RELEASE_TAGS"])


class MakefileTest(unittest.TestCase):
    def dry_run(self, target: str) -> str:
        result = subprocess.run(
            ["make", "--no-print-directory", "-n", target],
            cwd=ROOT,
            env={
                **os.environ,
                "CI_REGISTRY_USER": "",
                "CI_JOB_TOKEN": "",
                "DOCKER_HUB_USER": "",
                "DOCKER_HUB_PASSWORD": "",
            },
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("docker buildx build", result.stdout)
        return result.stdout

    def test_checks_reuse_scripts_without_building(self) -> None:
        output = self.dry_run("check-updates")
        self.assertIn("sh ci/check-ansible-release.sh", output)
        self.assertIn("sh ci/check-alpine-release.sh", output)
        output = self.dry_run("test-ci")
        self.assertIn("unittest discover", output)
        self.assertNotIn("docker run", output)

    def test_published_scan_pins_both_platforms_to_one_digest(self) -> None:
        output = self.dry_run("scan-published")
        self.assertEqual(output.count("registry_digest "), 1)
        self.assertIn("linux/amd64 linux/arm64", output)
        self.assertIn("@$digest", output)
        self.assertIn("--image-src remote", output)
        self.assertIn("--severity HIGH,CRITICAL", output)
        self.assertNotIn("docker.sock", output)

    def test_release_refuses_local_publication(self) -> None:
        result = subprocess.run(
            ["make", "--no-print-directory", "release", "GITLAB_CI=", "CI_JOB_NAME="],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("resource_group", result.stderr)
        self.assertNotIn("sh ci/release-image.sh", result.stdout)


if __name__ == "__main__":
    unittest.main()
