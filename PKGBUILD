# Fork: lbssousa/libfprint branch goodix-538d-sigfm-gtls
# Purpose-built for Goodix 538d (64x80 press sensor) with OpenCV-SIGFM matcher.
# Known-good commit: 4d9acb0013dd84903a9d1a16241a8fe2d4b2bf9c
pkgname=libfprint-goodix-538d
_pkgdirname=libfprint
pkgver=1.94.10
pkgrel=1
pkgdesc="Library for fingerprint readers - Goodix 538d (SIGFM/OpenCV matcher fork)"
arch=(x86_64)
url="https://github.com/lbssousa/libfprint"
license=(LGPL)
depends=('libgusb>=0.3.0' openssl pixman opencv)
makedepends=(git 'meson>=0.59.0' cmake pkg-config)
provides=(libfprint libfprint-2.so=2-64 libfprint-goodix-538d libfprint-git libfprint-2.so=2.64)
conflicts=(libfprint libfprint-goodix-521d)
groups=(fprint)
source=("git+https://github.com/lbssousa/libfprint.git#commit=4d9acb0013dd84903a9d1a16241a8fe2d4b2bf9c"
        "fix-tests-foreach.patch")
sha256sums=('SKIP'
            'SKIP')

prepare() {
  git -C ${_pkgdirname} apply ../fix-tests-foreach.patch
}

build() {
  arch-meson ${_pkgdirname} build -Dintrospection=false -Ddoc=false
  ninja -C build
}

package() {
  DESTDIR="$pkgdir" meson install -C build
}
