#!/usr/bin/env bash
# Dev-sandbox helper: waits for the latest iOS run on HEAD, prints steps + annotations.
R=theVentus/jubilant-octo-potato; SHA=$(git rev-parse HEAD)
until ID=$(gh api "repos/$R/actions/workflows/ios.yml/runs?head_sha=$SHA" --jq '.workflow_runs[0].id // empty') && [ -n "$ID" ]; do sleep 10; done
until s=$(gh api repos/$R/actions/runs/$ID --jq '.status+" "+(.conclusion//"")'); [[ $s == completed* ]]; do sleep 30; done
echo "run $ID: $s"
J=$(gh api repos/$R/actions/runs/$ID/jobs --jq '.jobs[0].id')
gh api repos/$R/actions/runs/$ID/jobs --jq '.jobs[0].steps[] | "\(.conclusion) \(.name)"' | grep -v '^success Post\|^success Set up\|^success Complete'
gh api repos/$R/check-runs/$J/annotations --jq '.[] | "[\(.annotation_level)] \(.message)"' | grep -v "capacity constraints"
