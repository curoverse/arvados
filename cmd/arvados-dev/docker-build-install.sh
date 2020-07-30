#!/bin/bash
# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

# Build an arvados-server-easy package, then install and run it on a
# base OS image.
#
# Examples:
#
#    docker-build-install.sh --force-buildimage --force-installimage     # always build fresh docker images
#
#    docker-build-install.sh                                             # reuse cached docker images if possible

set -e -o pipefail

declare -A opts=()
while [[ $# -gt 0 ]]; do
    arg="$1"
    shift
    case "$arg" in
        --force-buildimage)
            opts[force-buildimage]=1
            ;;
        --force-installimage)
            opts[force-installimage]=1
            ;;
        *)
            echo >&2 "invalid argument '$arg'"
            exit 2
            ;;
    esac
done

cleanup() {
    if [[ -n "${buildctr}" ]]; then
        docker rm "${buildctr}" || true
    fi
    if [[ -n "${installctr}" ]]; then
        docker rm "${installctr}" || true
    fi
}
trap cleanup ERR EXIT

version=$(git describe --tag --dirty)
osbase=debian:10

mkdir -p /tmp/pkg

buildimage=arvados-buildpackage-${osbase}
if [[ "${opts[force-buildimage]}" || -z "$(docker images --format {{.Repository}} "${buildimage}")" ]]; then
    (
        echo >&2 building arvados-server...
        cd cmd/arvados-server
        go install
    )
    echo >&2 building ${buildimage}...
    buildctr=${buildimage/:/-}
    docker rm "${buildctr}" || true
    docker run \
           --name "${buildctr}" \
           -v /tmp/pkg:/pkg \
           -v "${GOPATH:-${HOME}/go}"/bin/arvados-server:/arvados-server:ro \
           -v "$(pwd)":/arvados:ro \
           "${osbase}" \
           /arvados-server install \
           -type package \
           -source /arvados \
           -package-version "${version}"
    docker commit "${buildctr}" "${buildimage}"
    docker rm "${buildctr}"
    buildctr=
fi

pkgfile=/tmp/pkg/arvados-server-easy_${version}_amd64.deb
rm -v -f "${pkgfile}"

(
    echo >&2 building arvados-dev...
    cd cmd/arvados-dev
    go install
)
echo >&2 building ${pkgfile}...
docker run --rm \
       -v /tmp/pkg:/pkg \
       -v "${GOPATH:-${HOME}/go}"/bin/arvados-dev:/arvados-dev:ro \
       -v "$(pwd)":/arvados:ro \
       "${buildimage}" \
       /arvados-dev buildpackage \
       -source /arvados \
       -package-version "${version}" \
       -output-directory /pkg

ls -l ${pkgfile}
(
    echo >&2 dpkg-scanpackages...
    cd /tmp/pkg
    dpkg-scanpackages . | gzip > Packages.gz
)
sourcesfile=/tmp/sources.conf.d-arvados
echo >$sourcesfile "deb [trusted=yes] file:///pkg ./"

installimage="arvados-installpackage-${osbase}"
if [[ "${opts[force-installimage]}" || -z "$(docker images --format {{.Repository}} "${installimage}")" ]]; then
    echo >&2 building ${installimage}...
    installctr=${installimage/:/-}
    docker rm "${installctr}" || true
    docker run -it \
           --name "${installctr}" \
           -v /tmp/pkg:/pkg:ro \
           -v ${sourcesfile}:/etc/apt/sources.list.d/arvados-local.list:ro \
           "${osbase}" \
           bash -c 'apt update && DEBIAN_FRONTEND=noninteractive apt install -y arvados-server-easy postgresql'
    docker commit "${installctr}" "${installimage}"
    docker rm "${installctr}"
    installctr=
fi

echo >&2 installing ${pkgfile} in ${installimage}, then starting arvados...
docker run -it --rm \
       -v /tmp/pkg:/pkg:ro \
       -v ${sourcesfile}:/etc/apt/sources.list.d/arvados-local.list:ro \
       "${installimage}" \
       bash -c 'apt update && DEBIAN_FRONTEND=noninteractive apt install --reinstall -y arvados-server-easy postgresql && /etc/init.d/postgresql start && /var/lib/arvados/bin/arvados-server init -cluster-id x1234 && /var/lib/arvados/bin/arvados-server boot'
