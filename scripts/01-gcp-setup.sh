#!/bin/bash
set -e

PROJECT_ID=$(gcloud config get-value project)
echo "Setting up project: $PROJECT_ID"

echo ""
echo "Enabling required APIs..."
gcloud services enable \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  container.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com

echo ""
echo "Enter your Docker Hub username:"
read -r DOCKERHUB_USERNAME
echo -n "$DOCKERHUB_USERNAME" | gcloud secrets create dockerhub-username \
  --data-file=- \
  --replication-policy=automatic 2>/dev/null || \
  echo -n "$DOCKERHUB_USERNAME" | gcloud secrets versions add dockerhub-username --data-file=-

echo ""
echo "Enter your Docker Hub access token (Settings > Security > Access Tokens):"
read -rs DOCKERHUB_TOKEN
echo ""
echo -n "$DOCKERHUB_TOKEN" | gcloud secrets create dockerhub-token \
  --data-file=- \
  --replication-policy=automatic 2>/dev/null || \
  echo -n "$DOCKERHUB_TOKEN" | gcloud secrets versions add dockerhub-token --data-file=-

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
CB_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo ""
echo "Project Number: $PROJECT_NUMBER"
echo "Cloud Build Service Account: $CB_SA"

echo ""
echo "Granting project-level roles to: $CB_SA"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${CB_SA}" \
  --role="roles/storage.objectViewer" \
  --condition=None \
  --quiet

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${CB_SA}" \
  --role="roles/cloudbuild.builds.builder" \
  --condition=None \
  --quiet

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${CB_SA}" \
  --role="roles/logging.logWriter" \
  --condition=None \
  --quiet

echo ""
echo "Granting Secret Manager access..."

gcloud secrets add-iam-policy-binding dockerhub-username \
  --member="serviceAccount:${CB_SA}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet

gcloud secrets add-iam-policy-binding dockerhub-token \
  --member="serviceAccount:${CB_SA}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet

echo ""
echo "=========================================="
echo "GCP setup complete."
echo "=========================================="
echo ""