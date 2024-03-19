#!/bin/bash
set -e

source ./variables.sh

for build in ${BUILDS[@]}; do
    tag=${CONTAINER}/${build}:${VERSION}
    echo "building ${build} container with tag ${tag}"
    docker build -t ${tag} \
        -f Dockerfile \
        --build-arg debian_version="${DEBIAN_VERSION}" \
        --build-arg grpc_version="${GRPC_VERSION}" \
        --build-arg go_version="${GO_VERSION}" \
        --build-arg go_envoyproxy_pgv_version="${GO_ENVOYPROXY_PGV_VERSION}" \
        --build-arg go_mwitkow_gpv_version="${GO_MWITKOW_GPV_VERSION}" \
        --build-arg go_protoc_gen_go_version="${GO_PROTOC_GEN_GO_VERSION}" \
        --build-arg go_protoc_gen_go_grpc_version="${GO_PROTOC_GEN_GO_GRPC_VERSION}" \
        --target "${build}" \
        .

    if [ "${LATEST}" = true ]; then
        echo "setting ${tag} to latest"
        docker tag ${tag} ${CONTAINER}/${build}:latest
    fi
done
