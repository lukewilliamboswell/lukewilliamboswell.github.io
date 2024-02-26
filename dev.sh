#!/usr/bin/env bash

roc dev main.roc -- content docs

simple-http-server --nocache -i -p 3000 -- docs/
