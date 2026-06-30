# Deploying IndicatorComparison to the UW Statistics server

This app mirrors the [sae4health](https://github.com/wu-thomas/sae4health) deployment
model: a Dockerized Shiny app, published to a container registry by GitHub
Actions, and run on the UW Statistics server.

## What's automated (in this repo)

| Piece | File | What it does |
|-------|------|--------------|
| Container image | `Dockerfile` | `rocker/shiny:4.4` + dplyr/tidyr/readr/ggplot2/plotly; serves the app on port **3838**. |
| Auto-build/publish | `.github/workflows/docker-publish.yml` | On every push to `main`, builds the image and pushes it to `ghcr.io/<owner>/<repo>:latest`. |
| Server connection | `global.R` | Reads estimates from `server_link + "Gates_Indicator_Comparison/estimates/" + <Country> + "/combined_results.csv"`. Configurable via the `INDICATOR_SERVER_LINK` env var; defaults to the UW Stats base URL. |

## How the data path works

At runtime the app fetches, per selected country:

```
<server_link>/Gates_Indicator_Comparison/estimates/<Country>/combined_results.csv
```

- `server_link` defaults to `https://sites.stat.washington.edu/sae4health/`
  (same base the sae4health app uses), overridable with the `INDICATOR_SERVER_LINK`
  environment variable at `docker run` time.
- Country names are URL-encoded, so `Burkina Faso` becomes `Burkina%20Faso`.
- No data is baked into the image — estimates are read over the network, exactly
  as sae4health reads its `DHS_survey_dat/` files.

## Remaining steps to go live

1. **Confirm the public estimates URL** (needs UW Stats IT — see `email_to_Asa.md`).
   Verify the base URL and that the `Gates_Indicator_Comparison/estimates/<Country>/combined_results.csv`
   files are uploaded and web-readable.
2. **Push this repo to GitHub** (see "Step 3" below) so the Action publishes the image.
3. **Have the server pull and run the image** on port 3838, behind the UW reverse
   proxy, with auto-update on new image publishes (same mechanism as sae4health).

## Run locally with Docker (smoke test)

```bash
cd IndicatorComparison
docker build -t indicatorcomparison .
# point at a base URL that actually hosts the estimates:
docker run --rm -p 3838:3838 \
  -e INDICATOR_SERVER_LINK="https://sites.stat.washington.edu/sae4health/" \
  indicatorcomparison
# open http://localhost:3838
```

## Step 3 — put the repo on GitHub (one-time)

```bash
cd IndicatorComparison
git init -b main
git add .
git commit -m "IndicatorComparison Shiny app with Docker + CI"
gh repo create IndicatorComparison --public --source=. --remote=origin --push
```

After the first push, the **Docker** workflow runs automatically and publishes
`ghcr.io/<owner>/IndicatorComparison:latest`. Every later push to `main` rebuilds
and republishes it, which is what updates the app on the server.
