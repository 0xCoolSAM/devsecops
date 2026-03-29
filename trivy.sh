#!/bin/sh

dockerImageName=$(awk 'NR==1 {print $2}' Dockerfile)

echo "Scanning image: $dockerImageName"

trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  $dockerImageName

exit_code=$?

echo "Exit Code : $exit_code"

if [ "$exit_code" -eq 1 ]; then
  echo "Image scanning failed. Vulnerabilities found"
  exit 1
else
  echo "Image scanning passed. No HIGH or CRITICAL vulnerabilities found"
fi