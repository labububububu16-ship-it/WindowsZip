#!/usr/bin/env python3
"""Create ZIP files that do not carry macOS Finder metadata."""

import argparse
import json
import os
import sys
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path


MACOS_METADATA_NAMES = frozenset(
    {
        ".DS_Store",
        ".AppleDouble",
        ".AppleDesktop",
        ".LSOverride",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        ".DocumentRevisions-V100",
        ".VolumeIcon.icns",
        ".metadata_never_index",
        ".com.apple.timemachine.donotpresent",
        "Icon\r",
        "__MACOSX",
        ".localized",
    }
)


def is_macos_metadata(name):
    """Return whether a single path component is macOS-only metadata."""
    return name in MACOS_METADATA_NAMES or name.startswith("._")


def should_exclude(relative_parts):
    return any(is_macos_metadata(part) for part in relative_parts)


def default_output_path(source):
    source = Path(source)
    base_name = source.stem if source.is_file() and source.suffix else source.name
    candidate = source.parent / f"{base_name}-Windows.zip"
    if not candidate.exists():
        return candidate
    for index in range(2, 10000):
        candidate = source.parent / f"{base_name}-Windows {index}.zip"
        if not candidate.exists():
            return candidate
    raise RuntimeError("找不到可用的输出文件名。")


def path_is_inside(path, parent):
    try:
        Path(path).relative_to(Path(parent))
        return True
    except ValueError:
        return False


def _add_file(archive, source_file, archive_name):
    archive.write(str(source_file), arcname=archive_name)


def create_zip(source, output=None, overwrite=False):
    """Compress a file or folder and return a JSON-serializable summary."""
    source = Path(source).expanduser()
    if not source.exists() or source.is_symlink():
        raise ValueError(f"压缩源不存在，或不能是符号链接：{source}")
    source = source.resolve()

    output = Path(output).expanduser() if output else default_output_path(source)
    output = output.resolve()
    if output == source:
        raise ValueError("输出 ZIP 不能覆盖压缩源。")
    if source.is_dir() and path_is_inside(output, source):
        raise ValueError("输出 ZIP 不能放在待压缩的文件夹内部。")
    if output.exists() and not overwrite:
        raise FileExistsError(f"输出文件已存在：{output}（需要 --overwrite 才会覆盖）")
    if output.exists() and output.is_dir():
        raise ValueError(f"输出路径是文件夹，不是 ZIP 文件：{output}")

    output.parent.mkdir(parents=True, exist_ok=True)
    stats = {
        "added_files": 0,
        "added_directories": 0,
        "excluded_metadata": 0,
        "skipped_symlinks": 0,
        "excluded_examples": [],
    }
    started_at = datetime.now().isoformat(timespec="seconds")
    temporary_path = None

    def record_excluded(relative_parts):
        relative_name = "/".join(relative_parts)
        if len(stats["excluded_examples"]) < 20:
            stats["excluded_examples"].append(relative_name)
        stats["excluded_metadata"] += 1

    try:
        with tempfile.NamedTemporaryFile(
            prefix=f".{output.stem}-",
            suffix=".tmp",
            dir=str(output.parent),
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)

        with zipfile.ZipFile(
            str(temporary_path),
            mode="w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=6,
            allowZip64=True,
        ) as archive:
            if source.is_file():
                relative_parts = (source.name,)
                if should_exclude(relative_parts):
                    record_excluded(relative_parts)
                else:
                    _add_file(archive, source, source.name)
                    stats["added_files"] += 1
            else:
                root_name = source.name
                archive_name = f"{root_name}/"
                archive.writestr(archive_name, b"")
                stats["added_directories"] += 1

                for current_dir, dir_names, file_names in os.walk(
                    str(source), topdown=True, followlinks=False
                ):
                    current_path = Path(current_dir)
                    relative_dir = current_path.relative_to(source)
                    relative_dir_parts = () if str(relative_dir) == "." else relative_dir.parts

                    kept_dirs = []
                    for name in sorted(dir_names, key=str.casefold):
                        child_parts = relative_dir_parts + (name,)
                        child_path = current_path / name
                        if child_path.is_symlink():
                            stats["skipped_symlinks"] += 1
                        elif should_exclude(child_parts):
                            record_excluded(child_parts)
                        else:
                            kept_dirs.append(name)
                    dir_names[:] = kept_dirs

                    if relative_dir_parts:
                        directory_archive_name = "/".join((root_name,) + relative_dir_parts) + "/"
                        archive.writestr(directory_archive_name, b"")
                        stats["added_directories"] += 1

                    for name in sorted(file_names, key=str.casefold):
                        child_parts = relative_dir_parts + (name,)
                        child_path = current_path / name
                        if child_path.is_symlink():
                            stats["skipped_symlinks"] += 1
                        elif should_exclude(child_parts):
                            record_excluded(child_parts)
                        else:
                            archive_name = "/".join((root_name,) + child_parts)
                            _add_file(archive, child_path, archive_name)
                            stats["added_files"] += 1

        temporary_path.replace(output)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)

    return {
        "source": str(source),
        "output": str(output),
        "started_at": started_at,
        "finished_at": datetime.now().isoformat(timespec="seconds"),
        "size_bytes": output.stat().st_size,
        "stats": stats,
    }


def format_summary(summary):
    stats = summary["stats"]
    lines = [
        "压缩完成。",
        "",
        f"输出：{summary['output']}",
        f"文件：{stats['added_files']} 个，文件夹：{stats['added_directories']} 个",
        f"已排除 macOS 元数据：{stats['excluded_metadata']} 个",
    ]
    if stats["skipped_symlinks"]:
        lines.append(f"已跳过符号链接：{stats['skipped_symlinks']} 个")
    if stats["excluded_examples"]:
        lines.extend(["", "排除示例："] + [f"- {item}" for item in stats["excluded_examples"][:5]])
    return "\n".join(lines)


def write_report(summary, report_path):
    report = Path(report_path).expanduser()
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="压缩文件或文件夹，并排除 macOS Finder 元数据，方便 Windows 解压。"
    )
    parser.add_argument("source", help="要压缩的文件或文件夹")
    parser.add_argument("--output", help="输出 ZIP 路径；省略时生成 原名-Windows.zip")
    parser.add_argument("--overwrite", action="store_true", help="允许覆盖已存在的输出 ZIP")
    parser.add_argument("--report", help="额外写入 JSON 报告路径")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    summary = create_zip(
        source=args.source,
        output=args.output,
        overwrite=args.overwrite,
    )
    if args.report:
        write_report(summary, args.report)
    print(format_summary(summary))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"压缩失败：{exc}", file=sys.stderr)
        raise SystemExit(1)
