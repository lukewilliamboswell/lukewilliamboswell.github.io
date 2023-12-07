#!/usr/bin/env bash

roc run main.roc -- content docs

simple-http-server -i -- docs/
