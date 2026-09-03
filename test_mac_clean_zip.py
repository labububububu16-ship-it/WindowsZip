#!/usr/bin/env python3
import tempfile
import unittest
import zipfile
from pathlib import Path

from mac_clean_zip import create_zip


class MacCleanZipTests(unittest.TestCase):
    def test_excludes_macos_metadata_but_keeps_normal_mac_files(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "交付包"
            (root / "文档" / "子目录").mkdir(parents=True)
            (root / "文档" / "readme.txt").write_text("hello", encoding="utf-8")
            (root / "文档" / ".env").write_text("KEEP=1", encoding="utf-8")
            (root / "文档" / "子目录" / "image.png").write_bytes(b"png")
            (root / ".DS_Store").write_bytes(b"finder")
            (root / "文档" / "._readme.txt").write_bytes(b"appledouble")
            (root / "__MACOSX").mkdir()
            (root / "__MACOSX" / "._readme.txt").write_bytes(b"appledouble")
            (root / "文档" / ".localized").write_text("", encoding="utf-8")
            (root / "文档" / "说明.mac").write_text("metadata", encoding="utf-8")

            output = Path(temp_dir) / "交付包-Windows.zip"
            summary = create_zip(root, output)

            with zipfile.ZipFile(output) as archive:
                names = set(archive.namelist())
                self.assertIsNone(archive.testzip())

            self.assertIn("交付包/", names)
            self.assertIn("交付包/文档/readme.txt", names)
            self.assertIn("交付包/文档/.env", names)
            self.assertIn("交付包/文档/子目录/image.png", names)
            self.assertFalse(any(".DS_Store" in name for name in names))
            self.assertFalse(any("__MACOSX" in name for name in names))
            self.assertFalse(any("._" in Path(name).name for name in names))
            self.assertIn("交付包/文档/说明.mac", names)
            self.assertEqual(summary["stats"]["excluded_metadata"], 4)

    def test_refuses_output_inside_source_folder(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "资料"
            root.mkdir()
            (root / "a.txt").write_text("a", encoding="utf-8")

            with self.assertRaises(ValueError):
                create_zip(root, root / "资料-Windows.zip")


if __name__ == "__main__":
    unittest.main()
