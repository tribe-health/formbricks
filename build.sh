#!/bin/bash


docker build --platform linux/arm64 -t tribehealth/formbricks-multiplatform:arm64.8 --push -f apps/web/Dockerfile-skinny .
