#!/usr/bin/env bash

cd "$(dirname "$0")"

set -e

roc check main.roc

roc dev main.roc -- content docs

simple-http-server --nocache --ip 127.0.0.1 --index --open -- docs/
