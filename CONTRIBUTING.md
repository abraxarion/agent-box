# Contributing to agent-box

Thanks for helping make agent-box safer and easier to use.

## Before opening a change

- Search existing issues and pull requests.
- Keep proposals focused on host write isolation for coding-agent workflows.
- Use a private [GitHub security advisory](https://github.com/abraxarion/agent-box/security/advisories/new) for suspected vulnerabilities. Do not disclose them in a public issue.

## Development setup

agent-box has no third-party runtime dependencies beyond the tools listed in the README.

~~~bash
git clone https://github.com/abraxarion/agent-box.git
cd agent-box
./scripts/check-system.sh
./tests/run.sh
~~~

Most tests use temporary repositories and a fake Bubblewrap executable, so the complete test suite can run without opening a real sandbox.

## Making changes

1. Add a focused regression test before changing behavior.
2. Preserve the security invariants in [AGENTS.md](AGENTS.md).
3. Update [README.md](README.md), [SECURITY.md](SECURITY.md), and [CHANGELOG.md](CHANGELOG.md) when the public contract changes.
4. Keep Bash compatible with version 4.4 or newer and Python compatible with version 3.9 or newer.
5. Avoid new runtime dependencies unless the benefit clearly outweighs the audit and installation cost.

## Verification

Run these checks from the repository root:

~~~bash
./tests/run.sh
bash -n agent-box lib/*.sh libexec/git-policy libexec/git-send-pack-block scripts/*.sh tests/*.sh
shellcheck -x agent-box lib/*.sh libexec/git-policy libexec/git-send-pack-block scripts/*.sh tests/*.sh
PYTHONPYCACHEPREFIX=/tmp/agent-box-pycache python3 -m py_compile libexec/git-snapshot.py
git diff --check
~~~

For installer changes, also test an isolated prefix:

~~~bash
tmp_dir="$(mktemp -d)"
PREFIX="$tmp_dir/prefix" ./scripts/install.sh
"$tmp_dir/prefix/bin/agent-box" --version
rm -rf "$tmp_dir"
~~~

## Pull requests

Explain the user-visible behavior, security impact, and verification performed. Small pull requests are easier to audit and review.

By contributing, you agree that your contribution is licensed under the repository's [MIT License](LICENSE).
