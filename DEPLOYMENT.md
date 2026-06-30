# Deploying IndicatorComparison to the UW Statistics server

This app mirrors the [sae4health](https://github.com/wu-thomas/sae4health) deployment
model: a Dockerized Shiny app, published to a container registry by GitHub
Actions, and run on the UW Statistics server.

## What's automated (in this repo)

| Piece | File | What it does |
|-------|------|--------------|
| Container image | `Dockerfile` | `rocker/shiny:4.4` + dplyr/tidyr/readr/ggplot2/plotly; serves the app on port **3838**. |
| Auto-build/publish | `.github/workflows/docker-publish.yml` | On every push to `main`, builds the image and pushes it to `ghcr.io/<owner>/<repo>:latest`. |
| Data connection | `global.R` | Reads estimates from `server_link + "Gates_Indicator_Comparison/estimates/" + <Country> + "/combined_results.csv"`. Configurable via the `INDICATOR_SERVER_LINK` env var. |

## Two distinct locations (don't conflate them)

- **Deploy URL** — where users browse to the app:
  `https://sites.stat.washington.edu/indicatorcomparison/`. This is set up by the UW
  Stats reverse proxy (not by this app), alongside sae4health at `.../sae4health/`.
- **Data location (`server_link`)** — where the app *reads its estimates from*. This
  is a **separate internal server link**, NOT the deploy URL. (sae4health works the
  same way: served at `.../sae4health/` but its `DHS_survey_dat` lives at a different
  internal link.) The exact value must come from UW Stats IT — see `email_to_Asa.md`.

## How the data path works

At runtime the app fetches, per selected country:

```
<server_link>/Gates_Indicator_Comparison/estimates/<Country>/combined_results.csv
```

- `server_link` comes from the `INDICATOR_SERVER_LINK` environment variable, set at
  `docker run` time to the internal estimates URL provided by IT. (The unset default
  in `global.R` is a local Dropbox mirror, for development only.)
- It may be an `http(s)` URL (read over the network) or a local folder (read from
  disk) — `load_country_data()` detects which automatically.
- Country names are URL-encoded, so `Burkina Faso` becomes `Burkina%20Faso`.
- No data is baked into the image — estimates are read at runtime from `server_link`.

## Remaining steps to go live

1. **Get the internal data URL from UW Stats IT** (see `email_to_Asa.md`): where the
   `Gates_Indicator_Comparison/estimates/<Country>/combined_results.csv` files will be
   hosted, and confirm the container can read them. Set `INDICATOR_SERVER_LINK` to it.
2. **Set up the deploy URL** `https://sites.stat.washington.edu/indicatorcomparison/`
   in the reverse proxy (IT).
3. **Have the server pull and run the image** on port 3838 (with `INDICATOR_SERVER_LINK`
   set), behind the proxy, with auto-update on new image publishes (same mechanism as
   sae4health).

## Run locally with Docker (smoke test)

```bash
cd IndicatorComparison
docker build -t indicatorcomparison .
# point INDICATOR_SERVER_LINK at the internal URL/path that actually hosts the estimates:
docker run --rm -p 3838:3838 \
  -e INDICATOR_SERVER_LINK="<DATA_BASE_FROM_IT>/" \
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
