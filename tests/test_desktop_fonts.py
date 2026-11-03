"""Proportional desktop UI and fixed-width terminal/editor font policies."""
import configparser
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / ".config/fontconfig/conf.d/60-ubuntu-fonts.conf"


class DesktopFonts(unittest.TestCase):
    def test_proportional_ui_configs(self):
        for version in ("3.0", "4.0"):
            settings = configparser.ConfigParser()
            settings.read(ROOT / f".config/gtk-{version}/settings.ini")
            self.assertEqual(settings["Settings"]["gtk-font-name"], "Ubuntu Sans 11")

    def test_fixed_width_and_installer_defaults(self):
        self.assertRegex((ROOT / ".config/kitty/kitty.conf").read_text(), r"(?m)^font_family UbuntuMono Nerd Font Mono$")
        aliases = {alias.findtext("family"): alias for alias in ET.parse(POLICY).getroot().findall("alias")}
        self.assertEqual(aliases["sans-serif"].findtext("prefer/family"), "Ubuntu Sans")
        self.assertEqual(aliases["monospace"].findtext("prefer/family"), "UbuntuMono Nerd Font Mono")
        self.assertEqual(aliases["Ubuntu Sans"].findtext("accept/family"), "Symbols Nerd Font")
        installer = (ROOT / "install.sh").read_text()
        self.assertIn("ttf-ubuntu-sans", installer)
        self.assertIn("ttf-ubuntu-mono-nerd", installer)
        self.assertIn("monospace-font-name 'UbuntuMono Nerd Font Mono 11'", installer)
        self.assertNotIn("ttf-mononoki-nerd", installer)

    @unittest.skipUnless(shutil.which("fc-match"), "Fontconfig is not installed")
    def test_resolved_faces_spacing_and_icon_fallback(self):
        # Do not require the repository policy to have been stowed on the host.
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "fonts.conf"
            root = ET.Element("fontconfig")
            ET.SubElement(root, "include").text = "/etc/fonts/fonts.conf"
            ET.SubElement(root, "include").text = str(POLICY)
            ET.ElementTree(root).write(config, encoding="utf-8", xml_declaration=True)
            env = dict(os.environ, FONTCONFIG_FILE=str(config))

            def match(pattern):
                return subprocess.check_output(["fc-match", pattern, "-f", "%{family}|%{spacing}"],
                                               env=env, text=True).split("|")

            if match("Ubuntu Sans")[0] != "Ubuntu Sans" or match("UbuntuMono Nerd Font Mono")[0] != "UbuntuMono Nerd Font Mono":
                self.skipTest("Ubuntu Sans / Ubuntu Mono Nerd fonts are not installed")
            self.assertEqual(match("sans-serif")[0], "Ubuntu Sans")
            self.assertEqual(match("monospace"), ["UbuntuMono Nerd Font Mono", "100"])
            self.assertEqual(match("Ubuntu Mono"), ["UbuntuMono Nerd Font Mono", "100"])
            for codepoint in ("f002", "f489", "e0b0", "f02da"):
                self.assertEqual(match("Ubuntu Sans:charset=" + codepoint)[0], "Symbols Nerd Font")


if __name__ == "__main__":
    unittest.main()
