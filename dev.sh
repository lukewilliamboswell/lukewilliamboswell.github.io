#!/usr/bin/env bash

roc dev main.roc -- content docs

simple-http-server -i -- docs/
