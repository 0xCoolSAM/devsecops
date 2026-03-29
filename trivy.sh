#!/bin/sh

# dockerImageName=$(awk 'NR==1 {print $2}' Dockerfile)

# echo "Scanning image: $dockerImageName"

# trivy image --exit-code 0 --severity HIGH --light $dockerImageName

# trivy image --exit-code 1 --severity CRITICAL --light $dockerImageName

IMAGE=$1

echo "Scanning $IMAGE"

trivy image --exit-code 0 --severity HIGH --light $IMAGE
trivy image --exit-code 1 --severity CRITICAL --light $IMAGE
exit_code=$?

echo "Exit Code : $exit_code"

if [ "$exit_code" -eq 1 ]; then
    echo "Image scanning failed. Vulnerabilities found"
    exit 1
else
    echo "Image scanning passed. No CRITICAL vulnerabilities found"
fi