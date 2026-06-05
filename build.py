#!/usr/bin/env python3
import tomllib
import argparse
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
TOOLS_TOML = SCRIPT_DIR / "tools.toml"
DOCKERFILE_TPL = SCRIPT_DIR / "Dockerfile.tpl"
DOCKERFILE_OUT = SCRIPT_DIR / "Dockerfile"
README_FILE = SCRIPT_DIR / "README.md"

README_TABLE_START = "<!-- TOOLS_TABLE_START -->"
README_TABLE_END = "<!-- TOOLS_TABLE -->"


def load_tools(toml_path: Path) -> dict:
    with open(toml_path, "rb") as f:
        return tomllib.load(f)


def gen_package_list(tools: dict) -> str:
    packages = tools.get("package", [])
    return " ".join(p["name"] for p in packages)


def gen_stage_from_blocks(tools: dict) -> str:
    images = tools.get("image", [])
    if not images:
        return ""
    lines = []
    for img in images:
        alias = img["name"].replace("-", "_") + "_extractor"
        lines.append(f"FROM {img['image']} AS {alias}")
    return "\n".join(lines) + "\n"


def gen_stage_copy_blocks(tools: dict) -> str:
    images = tools.get("image", [])
    if not images:
        return ""
    lines = []
    for img in images:
        alias = img["name"].replace("-", "_") + "_extractor"
        lines.append(f"COPY --from={alias} {img['source']} {img['dest']}")
    return "\n".join(lines) + "\n"


def fetch_latest_release(repo: str) -> dict:
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    headers = {"User-Agent": "code-server-plus"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def resolve_binary_url(binary: dict) -> tuple[str, str]:
    release = fetch_latest_release(binary["repo"])
    version = release["tag_name"]
    pattern = binary["pattern"]
    matches = [a for a in release["assets"] if pattern in a["name"]]
    if not matches:
        raise ValueError(
            f"未找到匹配 '{pattern}' 的 asset（{binary['repo']} {version}）"
        )
    x86_keywords = ["x86_64", "x64", "amd64"]
    for m in matches:
        if any(k in m["name"] for k in x86_keywords):
            return m["browser_download_url"], version
    return matches[0]["browser_download_url"], version


def gen_binary_blocks(tools: dict) -> str:
    binaries = tools.get("binary", [])
    if not binaries:
        return ""
    lines = []
    for bin_item in binaries:
        url, version = resolve_binary_url(bin_item)
        name = bin_item["name"]
        extract = bin_item.get("extract", name)
        print(f"  {name}: {version} <- {url}")
        if ".tar." in url:
            lines.append(
                f"RUN curl -L '{url}' -o /tmp/{name}.tar "
                f"&& tar xf /tmp/{name}.tar -C /tmp "
                f"&& find /tmp -type f -name '{extract}' "
                f"-exec mv {{}} /usr/local/bin/{name} \\; "
                f"&& chmod +x /usr/local/bin/{name} "
                f"&& rm -f /tmp/{name}.tar"
            )
        elif url.endswith(".tgz"):
            lines.append(
                f"RUN curl -L '{url}' -o /tmp/{name}.tgz "
                f"&& tar xf /tmp/{name}.tgz -C /tmp "
                f"&& find /tmp -type f -name '{extract}' "
                f"-exec mv {{}} /usr/local/bin/{name} \\; "
                f"&& chmod +x /usr/local/bin/{name} "
                f"&& rm -f /tmp/{name}.tgz"
            )
        elif url.endswith(".zip"):
            lines.append(
                f"RUN curl -L '{url}' -o /tmp/{name}.zip "
                f"&& unzip -o /tmp/{name}.zip -d /tmp/{name} "
                f"&& find /tmp/{name} -type f -name '{extract}' "
                f"-exec mv {{}} /usr/local/bin/{name} \\; "
                f"&& chmod +x /usr/local/bin/{name} "
                f"&& rm -rf /tmp/{name}.zip /tmp/{name}"
            )
        else:
            lines.append(
                f"RUN curl -L '{url}' -o /usr/local/bin/{name} "
                f"&& chmod +x /usr/local/bin/{name}"
            )
    return "\n".join(lines) + "\n"


def gen_extension_blocks(tools: dict) -> str:
    extensions = tools.get("extension", [])
    if not extensions:
        return ""
    lines = []
    for ext in extensions:
        lines.append(f"RUN code-server --install-extension {ext['name']}")
    return "\n".join(lines) + "\n"


def gen_dockerfile(tpl_path: Path, tools: dict) -> str:
    tpl = tpl_path.read_text()
    replacements = {
        "{{BASE_IMAGE}}": f"{tools['base']['image']}:{tools['base']['tag']}",
        "{{STAGE_FROM_BLOCKS}}": gen_stage_from_blocks(tools),
        "{{PACKAGE_LIST}}": gen_package_list(tools),
        "{{STAGE_COPY_BLOCKS}}": gen_stage_copy_blocks(tools),
        "{{BINARY_DOWNLOADS}}": gen_binary_blocks(tools),
        "{{EXTENSION_INSTALLS}}": gen_extension_blocks(tools),
    }
    result = tpl
    for placeholder, value in replacements.items():
        result = result.replace(placeholder, value)
    return result


def gen_tools_table(tools: dict) -> str:
    categories = [
        ("package", "包管理器安装"),
        ("image", "镜像提取"),
        ("binary", "二进制下载"),
        ("extension", "扩展安装"),
    ]
    rows = []
    for key, label in categories:
        items = tools.get(key, [])
        if not items:
            continue
        rows.append(f"### {label}")
        rows.append("")
        rows.append("| 名称 | 说明 |")
        rows.append("|------|------|")
        for item in items:
            name = item["name"]
            desc = item.get("desc", "")
            rows.append(f"| {name} | {desc} |")
        rows.append("")
    return "\n".join(rows)


def update_readme(tools: dict) -> None:
    table = gen_tools_table(tools)
    content = README_FILE.read_text() if README_FILE.exists() else ""

    if README_TABLE_START in content and README_TABLE_END in content:
        before = content[: content.index(README_TABLE_START)]
        after = content[content.index(README_TABLE_END) + len(README_TABLE_END) :]
        content = f"{before}{README_TABLE_START}\n{table}\n{README_TABLE_END}{after}"
    else:
        content = content.rstrip() + "\n\n"
        content += f"{README_TABLE_START}\n{table}\n{README_TABLE_END}\n"

    README_FILE.write_text(content)


def cmd_generate(args: argparse.Namespace) -> None:
    tools = load_tools(TOOLS_TOML)
    dockerfile = gen_dockerfile(DOCKERFILE_TPL, tools)
    DOCKERFILE_OUT.write_text(dockerfile)
    print(f"已生成 {DOCKERFILE_OUT}")
    update_readme(tools)
    print(f"已更新 {README_FILE}")


def cmd_build(args: argparse.Namespace) -> None:
    tools = load_tools(TOOLS_TOML)
    cmd_generate(args)
    image_name = args.name
    base_tag = tools["base"]["tag"]
    date_part = subprocess.run(
        ["date", "+%Y%m%d"], capture_output=True, text=True
    ).stdout.strip()
    tag = args.tag or f"{base_tag}-{date_part}"
    print(f"构建镜像: {image_name}:{tag}")
    subprocess.run(
        [
            "docker",
            "build",
            "-t",
            f"{image_name}:{tag}",
            "-t",
            f"{image_name}:latest",
            str(SCRIPT_DIR),
        ],
        check=True,
    )
    print(f"构建完成: {image_name}:{tag}")
    subprocess.run(["docker", "images", image_name], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="code-server-plus 构建工具")
    sub = parser.add_subparsers(dest="command")

    p_gen = sub.add_parser("generate", help="生成 Dockerfile 和 README")
    p_gen.set_defaults(func=cmd_generate)

    p_build = sub.add_parser("build", help="生成并构建 Docker 镜像")
    p_build.add_argument("--name", default="tecpoirot/code-server-plus", help="镜像名称")
    p_build.add_argument("--tag", default=None, help="镜像标签（默认: {base_tag}-{YYYYMMDD}）")
    p_build.set_defaults(func=cmd_build)

    args = parser.parse_args()
    if not hasattr(args, "func"):
        parser.print_help()
        sys.exit(1)
    args.func(args)


if __name__ == "__main__":
    main()
