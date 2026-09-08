# Installing Bubblewrap 0.12.0 or newer

agent-box requires Bubblewrap 0.12.0 or newer. Earlier releases are affected by [GHSA-pxhw-h44j-8pfx](https://github.com/containers/bubblewrap/security/advisories/GHSA-pxhw-h44j-8pfx), a sandbox-setup symlink traversal issue fixed in 0.12.0.

## Check the installed version

~~~bash
bwrap --version
~~~

The reported version must be 0.12.0 or newer.

## Install from a distribution

Use your distribution's package manager first, then verify the installed version.

### Debian and Ubuntu

~~~bash
sudo apt update
sudo apt install bubblewrap
~~~

### Fedora

~~~bash
sudo dnf install bubblewrap
~~~

### Arch Linux

~~~bash
sudo pacman -S bubblewrap
~~~

Distribution repositories do not all publish security updates at the same time. If the package manager installs a version older than 0.12.0, update from another trusted distribution channel or build the official release from source.

## Build the official release from source

Download `bubblewrap-0.12.0.tar.xz` from the official [Bubblewrap 0.12.0 release](https://github.com/containers/bubblewrap/releases/tag/v0.12.0).

On Debian or Ubuntu, install the build dependencies:

~~~bash
sudo apt update
sudo apt install --yes \
  build-essential \
  libcap-dev \
  libselinux1-dev \
  meson \
  ninja-build \
  pkg-config \
  python3
~~~

Extract, build, test, and install:

~~~bash
tar -xf bubblewrap-0.12.0.tar.xz
cd bubblewrap-0.12.0
meson setup build --prefix=/usr/local
meson compile -C build
meson test -C build
sudo meson install -C build
hash -r
bwrap --version
~~~

Use the checksum published with the release when available, and download release artifacts only from a source you trust.

## Check which executable is selected

If an older distribution package and a newer source installation both exist:

~~~bash
type -a bwrap
command -v bwrap
bwrap --version
~~~

`/usr/local/bin` normally precedes `/usr/bin`. Open a new shell or run `hash -r` if Bash cached the older path.

## Verify user namespaces

Bubblewrap 0.12.0 no longer supports a setuid build. It relies on unprivileged Linux user namespaces.

~~~bash
bwrap \
  --ro-bind / / \
  --proc /proc \
  --dev /dev \
  --unshare-pid \
  /bin/sh -c 'echo "Bubblewrap works"'
~~~

If this fails while creating a user namespace, check the kernel and distribution security policy for unprivileged user-namespace restrictions.

When Bubblewrap is ready, return to the [agent-box quick start](../README.md#quick-start).
