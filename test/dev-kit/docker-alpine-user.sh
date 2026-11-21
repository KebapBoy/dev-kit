#!/bin/bash
# docker: true under Sysbox, container user without root and without sudo of its own (node in the
# official node image, like dev in the examples): dockerd starts through the narrow sudo rule
cd "$(dirname "$0")" && DEV_KIT_TEST_SUDO=narrow exec ./docker.sh
