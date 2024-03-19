ARG debian_version
ARG go_version
ARG grpc_version
ARG go_envoyproxy_pgv_version
ARG go_mwitkow_gpv_version
ARG go_protoc_gen_go_version
ARG go_protoc_gen_go_grpc_version
ARG go_protoc_gen_go_ttrpc_version

FROM golang:$go_version-$debian_version AS build

# TIL docker arg variables need to be redefined in each build stage
ARG grpc_version
ARG go_envoyproxy_pgv_version
ARG go_mwitkow_gpv_version
ARG go_protoc_gen_go_version
ARG go_protoc_gen_go_grpc_version
ARG go_protoc_gen_go_ttrpc_version

RUN set -ex && apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    cmake \
    curl \
    git \
    unzip \
    libtool \
    autoconf \
    zlib1g-dev \
    libssl-dev \
    clang

WORKDIR /tmp
RUN git clone --depth 1 --shallow-submodules -b v$grpc_version.x --recursive https://github.com/grpc/grpc && \
    git clone --depth 1 https://github.com/googleapis/googleapis && \
    git clone --depth 1 https://github.com/googleapis/api-common-protos

ARG bazel=/tmp/grpc/tools/bazel

WORKDIR /tmp/grpc
RUN $bazel build //external:protocol_compiler && \
    $bazel build //src/compiler:all && \
    $bazel build //test/cpp/util:grpc_cli

WORKDIR /tmp
# Install protoc required by envoyproxy/protoc-gen-validate package
RUN cp -a /tmp/grpc/bazel-bin/external/com_google_protobuf/. /usr/local/bin/
# Copy well known proto files required by envoyproxy/protoc-gen-validate package
RUN mkdir -p /usr/local/include/google/protobuf && \
    cp -a /tmp/grpc/bazel-grpc/external/com_google_protobuf/src/google/protobuf/. /usr/local/include/google/protobuf/

# go install go-related bins
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@${go_protoc_gen_go_grpc_version}
RUN go install github.com/containerd/ttrpc/cmd/protoc-gen-go-ttrpc@${go_protoc_gen_go_ttrpc_version}

RUN go install github.com/gogo/protobuf/protoc-gen-gogo@latest
RUN go install github.com/gogo/protobuf/protoc-gen-gogofast@latest

RUN go install github.com/ckaznocha/protoc-gen-lint@latest

RUN go install github.com/pseudomuto/protoc-gen-doc/cmd/protoc-gen-doc@latest

RUN go install github.com/micro/micro/v3/cmd/protoc-gen-micro@latest

RUN go install github.com/envoyproxy/protoc-gen-validate@v${go_envoyproxy_pgv_version}

RUN go install github.com/gomatic/renderizer/v2/cmd/renderizer@latest

# Origin protoc-gen-go should be installed last, for not been overwritten by any other binaries(see #210)
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@${go_protoc_gen_go_version}

RUN go install github.com/mwitkow/go-proto-validators/protoc-gen-govalidators@v${go_mwitkow_gpv_version}

FROM debian:$debian_version-slim AS protoc-all

ARG grpc_version

ARG go_envoyproxy_pgv_version
ARG go_mwitkow_gpv_version

RUN mkdir -p /usr/share/man/man1
RUN set -ex && apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    software-properties-common \
    ca-certificates \
    zlib1g \
    libssl1.1 \
    dos2unix \
    gawk

COPY --from=build /tmp/googleapis/google/ /opt/include/google
COPY --from=build /tmp/api-common-protos/google/ /opt/include/google

# Copy well known proto files
COPY --from=build /tmp/grpc/bazel-grpc/external/com_google_protobuf/src/google/protobuf/ /opt/include/google/protobuf/
# Copy protoc
COPY --from=build /tmp/grpc/bazel-bin/external/com_google_protobuf/ /usr/local/bin/
# Copy protoc default plugins
COPY --from=build /tmp/grpc/bazel-bin/src/compiler/ /usr/local/bin/
# Copy grpc_cli
COPY --from=build /tmp/grpc/bazel-bin/test/cpp/util/ /usr/local/bin/

COPY --from=build /go/bin/* /usr/local/bin/

# ttrpc requires protoc-gen-ttrpc not protoc-gen-go-ttprc
RUN ln /usr/local/bin/protoc-gen-go-ttrpc /usr/local/bin/protoc-gen-ttrpc

COPY --from=build /go/pkg/mod/github.com/envoyproxy/protoc-gen-validate@v${go_envoyproxy_pgv_version}/ /opt/include/

COPY --from=build /go/pkg/mod/github.com/mwitkow/go-proto-validators@v${go_mwitkow_gpv_version}/ /opt/include/github.com/mwitkow/go-proto-validators/

ADD all/entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /defs
ENTRYPOINT [ "entrypoint.sh" ]

# protoc
FROM protoc-all AS protoc
ENTRYPOINT [ "protoc", "-I/opt/include" ]

# grpc-cli
FROM protoc-all as grpc-cli

ADD ./cli/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /run
ENTRYPOINT [ "/entrypoint.sh" ]
