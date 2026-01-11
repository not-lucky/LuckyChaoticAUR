#!/usr/bin/env python3
"""
generate-index.py - Generate HTML package index and packages.json for GitHub Pages

This script:
1. Reads packages.yaml for configuration
2. Parses .SRCINFO files from built packages
3. Extracts package metadata from pkg.tar.zst files
4. Generates packages.json for the web interface
5. Optionally generates a static HTML index

Usage:
    python scripts/generate-index.py [--repo-dir REPO_DIR] [--output-dir OUTPUT_DIR]
"""

import argparse
import json
import os
import subprocess
import tarfile
import tempfile
from datetime import datetime
from pathlib import Path

import yaml


def parse_pkginfo(pkginfo_content: str) -> dict:
    """Parse .PKGINFO file content into a dictionary."""
    info = {}
    for line in pkginfo_content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' in line:
            key, _, value = line.partition('=')
            key = key.strip()
            value = value.strip()
            # Handle multi-value fields
            if key in info:
                if isinstance(info[key], list):
                    info[key].append(value)
                else:
                    info[key] = [info[key], value]
            else:
                info[key] = value
    return info


def extract_package_info(pkg_path: Path) -> dict:
    """Extract package info from a .pkg.tar.zst file."""
    try:
        # Use zstd to decompress and tar to extract .PKGINFO
        with tempfile.TemporaryDirectory() as tmpdir:
            result = subprocess.run(
                ['tar', '-I', 'zstd', '-xf', str(pkg_path), '-C', tmpdir, '.PKGINFO'],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                print(f"Warning: Could not extract .PKGINFO from {pkg_path.name}")
                return {}

            pkginfo_path = Path(tmpdir) / '.PKGINFO'
            if pkginfo_path.exists():
                content = pkginfo_path.read_text()
                return parse_pkginfo(content)
    except Exception as e:
        print(f"Error extracting {pkg_path.name}: {e}")
    return {}


def get_file_mtime(path: Path) -> str:
    """Get file modification time as ISO format string."""
    try:
        mtime = os.path.getmtime(path)
        return datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M')
    except:
        return ''


def load_packages_yaml(yaml_path: Path) -> dict:
    """Load and parse packages.yaml configuration."""
    if not yaml_path.exists():
        return {'repository': {'name': 'repo'}, 'packages': []}
    with open(yaml_path) as f:
        return yaml.safe_load(f) or {}


def scan_packages(repo_dir: Path) -> list:
    """Scan repository directory for package files and extract metadata."""
    packages = []
    pkg_dir = repo_dir / 'x86_64'

    if not pkg_dir.exists():
        print(f"Package directory not found: {pkg_dir}")
        return packages

    for pkg_file in sorted(pkg_dir.glob('*.pkg.tar.zst')):
        # Skip signature files
        if pkg_file.suffix == '.sig':
            continue

        print(f"Processing: {pkg_file.name}")
        info = extract_package_info(pkg_file)

        if info:
            package = {
                'name': info.get('pkgname', pkg_file.stem.split('-')[0]),
                'version': info.get('pkgver', 'unknown'),
                'description': info.get('pkgdesc', ''),
                'url': info.get('url', ''),
                'license': info.get('license', ''),
                'arch': info.get('arch', 'x86_64'),
                'size': info.get('size', ''),
                'build_date': get_file_mtime(pkg_file),
                'filename': pkg_file.name,
                'depends': info.get('depend', []) if isinstance(info.get('depend'), list) else [info.get('depend')] if info.get('depend') else [],
            }
            packages.append(package)
        else:
            # Fallback: extract info from filename
            # Format: name-version-rel-arch.pkg.tar.zst
            parts = pkg_file.stem.replace('.pkg.tar', '').rsplit('-', 3)
            if len(parts) >= 2:
                packages.append({
                    'name': parts[0],
                    'version': '-'.join(parts[1:-1]) if len(parts) > 2 else parts[1],
                    'description': '',
                    'build_date': get_file_mtime(pkg_file),
                    'filename': pkg_file.name,
                })

    return packages


def generate_packages_json(packages: list, config: dict, output_path: Path):
    """Generate packages.json file for web interface."""
    data = {
        'repository': config.get('repository', {}).get('name', 'repo'),
        'last_updated': datetime.now().strftime('%Y-%m-%d %H:%M UTC'),
        'package_count': len(packages),
        'packages': packages
    }

    with open(output_path, 'w') as f:
        json.dump(data, f, indent=2)

    print(f"Generated: {output_path}")


def generate_static_html(packages: list, config: dict, template_path: Path, output_path: Path):
    """Generate static HTML with embedded package data (optional)."""
    if not template_path.exists():
        print(f"Template not found: {template_path}")
        return

    template = template_path.read_text()

    # Build package rows
    rows = []
    for pkg in packages:
        row = f'''                    <tr>
                        <td><a href="https://aur.archlinux.org/packages/{pkg['name']}" target="_blank">{pkg['name']}</a></td>
                        <td><code>{pkg.get('version', '-')}</code></td>
                        <td>{pkg.get('description', '-')}</td>
                        <td>{pkg.get('build_date', '-')}</td>
                    </tr>'''
        rows.append(row)

    # Replace placeholder in template
    if rows:
        package_rows = '\n'.join(rows)
        # Replace the placeholder row
        template = template.replace(
            '''                    <tr class="placeholder">
                        <td colspan="4">Loading packages...</td>
                    </tr>''',
            package_rows
        )

    # Update counts
    template = template.replace(
        '<span class="value" id="package-count">--</span>',
        f'<span class="value" id="package-count">{len(packages)}</span>'
    )
    template = template.replace(
        '<span class="value" id="last-updated">--</span>',
        f'<span class="value" id="last-updated">{datetime.now().strftime("%Y-%m-%d %H:%M")}</span>'
    )

    output_path.write_text(template)
    print(f"Generated: {output_path}")


def main():
    parser = argparse.ArgumentParser(description='Generate package index for GitHub Pages')
    parser.add_argument('--repo-dir', type=Path, default=Path('./repo'),
                        help='Repository directory containing packages')
    parser.add_argument('--output-dir', type=Path, default=Path('./repo'),
                        help='Output directory for generated files')
    parser.add_argument('--config', type=Path, default=Path('./packages.yaml'),
                        help='Path to packages.yaml configuration')
    parser.add_argument('--template', type=Path, default=Path('./web/index.html'),
                        help='Path to HTML template')
    parser.add_argument('--static', action='store_true',
                        help='Generate static HTML with embedded data')

    args = parser.parse_args()

    # Load configuration
    config = load_packages_yaml(args.config)
    print(f"Repository: {config.get('repository', {}).get('name', 'unknown')}")

    # Scan packages
    packages = scan_packages(args.repo_dir)
    print(f"Found {len(packages)} package(s)")

    # Ensure output directory exists
    args.output_dir.mkdir(parents=True, exist_ok=True)

    # Generate packages.json
    generate_packages_json(packages, config, args.output_dir / 'packages.json')

    # Optionally generate static HTML
    if args.static:
        generate_static_html(
            packages,
            config,
            args.template,
            args.output_dir / 'index.html'
        )


if __name__ == '__main__':
    main()
