#!/bin/bash
set -e

echo "Submitting build to Google Cloud Build..."
gcloud builds submit --config=cloudbuild.yaml .

echo ""
echo "Build complete. Verify at: https://hub.docker.com/r/<your-username>/nagp-api"