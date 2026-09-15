"""Tests for the apple-device-tools package.

The program it ships is a session on hardware -- choose a connected device,
install the bundle, launch it by identifier, attach its output. These tests
assert what can be checked without a device, because the recipe declares
`macosx` only and no hosted runner has an iOS device attached. The refusals are
run on macOS in .github/workflows/apple-runners.yml.
"""
import os
import re

import pytest
from tests.lib.xpkg_parser import parse_xpkg
from tests.lib.assertions import (
    assert_required_fields, assert_valid_spec, assert_valid_type,
    assert_no_typos, assert_no_exec_xvm, assert_no_bashrc_modification,
    assert_no_direct_path_modification, assert_uses_new_api,
    assert_xim_add_succeeds,
)
from tests.lib.platform_utils import skip_if_not

PKG = "apple-device-tools"
PKG_FILE = "pkgs/a/apple-device-tools.lua"


@pytest.fixture(scope='module')
def meta():
    return parse_xpkg(PKG_FILE)


@pytest.fixture(scope='module')
def source_text():
    from tests.lib.platform_utils import project_root
    with open(os.path.join(project_root(), PKG_FILE), encoding="utf-8") as handle:
        return handle.read()


@pytest.fixture(scope='module')
def script(source_text):
    m = re.search(r'\[==\[(.*?)\]==\]', source_text, re.S)
    assert m, "the embedded devicectl-run script was not found"
    return m.group(1)


@pytest.fixture(scope='module')
def script_code(script):
    """The program without its comments: assertions about behaviour must not
    match the comment that explains a choice."""
    return "\n".join(l for l in script.splitlines()
                     if not l.lstrip().startswith("#"))


class TestStatic:
    @pytest.mark.static
    def test_required_fields(self, meta):
        assert_required_fields(meta)

    @pytest.mark.static
    def test_valid_spec(self, meta):
        assert_valid_spec(meta)

    @pytest.mark.static
    def test_valid_type(self, meta):
        assert_valid_type(meta)

    @pytest.mark.static
    def test_no_typos(self):
        assert_no_typos(PKG_FILE)

    @pytest.mark.static
    def test_no_exec_xvm(self):
        assert_no_exec_xvm(PKG_FILE)

    @pytest.mark.static
    def test_no_bashrc(self):
        assert_no_bashrc_modification(PKG_FILE)

    @pytest.mark.static
    def test_no_path_modification(self):
        assert_no_direct_path_modification(PKG_FILE)

    @pytest.mark.static
    def test_new_api(self):
        assert_uses_new_api(PKG_FILE)

    @pytest.mark.static
    def test_macosx_only_and_no_url(self, source_text):
        """devicectl ships inside Xcode; there is nothing to package."""
        code = re.sub(r'--.*', '', source_text)
        assert 'macosx' in code
        for other in ('linux', 'windows'):
            assert not re.search(r'\b' + other + r'\s*=\s*\{', code)
        assert 'url' not in code

    @pytest.mark.static
    def test_the_script_is_valid_shell(self, script, tmp_path):
        import subprocess
        p = tmp_path / "devicectl-run"
        p.write_text(script, encoding="utf-8")
        r = subprocess.run(["bash", "-n", str(p)], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr

    @pytest.mark.static
    def test_no_set_e_around_the_launch(self, script_code):
        """`set -e` would end the script on a non-zero launch instead of
        returning that status."""
        assert 'set -e\n' not in script_code and 'set -euo' not in script_code
        assert re.search(r'process launch --device "\$device" --terminate-existing --console "\$bundle_id" "\$@"\nexit \$\?',
                         script_code)

    @pytest.mark.static
    def test_install_precedes_launch(self, script_code):
        install = script_code.index('xcrun devicectl device install app --device "$device" "$app"')
        assert install < script_code.index("process launch --device")

    @pytest.mark.static
    def test_devices_are_read_as_json(self, script_code):
        assert 'devicectl list devices --json-output' in script_code
        assert 'tunnelState' in script_code

    @pytest.mark.static
    def test_a_device_can_be_named(self, script):
        assert 'DEVICECTL_RUN_DEVICE' in script

    @pytest.mark.static
    def test_a_simulator_bundle_is_refused(self, script_code):
        assert 'CFBundleSupportedPlatforms' in script_code
        assert 'iPhoneSimulator' in script_code

    @pytest.mark.static
    def test_the_unmeasured_status_is_said(self, script, source_text):
        """Until a device measurement replaces it, the launch says its status is
        devicectl's, the discipline apple-simulator-tools 0.3.0 applied."""
        assert "not yet measured to be the program's" in script
        assert "not yet measured" in source_text

    @pytest.mark.static
    def test_every_refusal_names_what_is_missing(self, script):
        for wanted in ('no xcrun', 'finds no devicectl', 'is not a .app bundle',
                       'no connected iOS device', 'could not read CFBundleIdentifier'):
            assert wanted in script, f"no refusal names: {wanted}"
        assert script.count('>&2') >= 8, "refusals are not on stderr"

    @pytest.mark.static
    def test_the_program_goes_in_bin_and_is_registered_there(self, source_text):
        code = re.sub(r'--.*', '', source_text)
        assert re.search(r'bindir\s*=\s*path\.join\(dir,\s*"bin"\)', code)
        assert re.search(r'program\s*=\s*path\.join\(bindir', code)
        assert re.search(r'xvm\.add\("devicectl-run",\s*\{\s*bindir\s*=\s*dir', code)


class TestIndex:
    @pytest.mark.index
    def test_xim_add(self):
        assert_xim_add_succeeds(PKG_FILE)


class TestVerify:
    @pytest.mark.verify
    @skip_if_not('macosx')
    def test_installed_program_is_executable(self):
        from tests.lib.platform_utils import xpkgs_dir
        import glob
        hits = []
        for ns in ("xim", "local"):
            hits += sorted(glob.glob(os.path.join(
                xpkgs_dir(), f"{ns}-x-apple-device-tools", "*", "bin", "devicectl-run")))
        assert hits, "no installed bin/devicectl-run found"
        assert os.access(hits[-1], os.X_OK), f"{hits[-1]} is not executable"
