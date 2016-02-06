#!/bin/sh

TOP_DIR=$(git rev-parse --show-toplevel)

pushd $TOP_DIR

cd src && ln -s $HOME/.bazel/tools

popd
