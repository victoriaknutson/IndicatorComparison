Subject: Deploying a new Shiny app (IndicatorComparison) on the Stats server

Hi Asa,

We have a new R Shiny app, "IndicatorComparison," that we'd like to deploy on the
UW Statistics server. It's set up the same way as the sae4health app
(https://github.com/wu-thomas/sae4health): containerized with Docker and
auto-published to the GitHub Container Registry (ghcr.io) by a GitHub Actions
workflow on every push. The app is lightweight — it just reads pre-modeled CSV
estimates and draws scatterplots, so there's no modeling, and no spatial/INLA
dependencies. The container serves on port 3838.

A few things I'd like to check on your end to get it connected and deployed.
There are two separate locations involved — where the app is served to users, and
where the app reads its data from — so I've split them out below.

1. Where the app is served (deploy URL). We'd like it served at
       https://sites.stat.washington.edu/indicatorcomparison/
   alongside sae4health (which is at .../sae4health/). The container listens on
   port 3838. Can you set up that path in the reverse proxy / nginx config, or
   should it live at a different URL?

2. Where the app reads its data (internal estimates location). Separately from the
   deploy URL above, the app fetches per-country estimate files at runtime from:
       <DATA_BASE>/Gates_Indicator_Comparison/estimates/<Country>/combined_results.csv
   For sae4health, I understand the data (DHS_survey_dat) isn't under the app's
   public URL but at a different internal server link. We'd like the same kind of
   setup. Could you let us know:
     - What base URL / internal path should we use as <DATA_BASE> for the estimates?
       We'll point the app at it via the INDICATOR_SERVER_LINK environment variable.
     - Where should we place the "Gates_Indicator_Comparison/estimates/..." files so
       the app can read them (and confirm they'll be reachable from the container)?
       We can hand off the per-country combined_results.csv files.

3. Pulling and running the image. The CI publishes the (public) image
   ghcr.io/victoriaknutson/indicatorcomparison:latest. Could you confirm how the
   server should pull and run it (the same way sae4health is run)? Specifically:
     - The image is public, so the server can pull from ghcr.io without credentials.
     - The app needs INDICATOR_SERVER_LINK set to <DATA_BASE> at run time, e.g.
       `docker run -e INDICATOR_SERVER_LINK="<DATA_BASE>/" -p 3838:3838 <image>`.
     - What's the mechanism to auto-update the running container when a new image is
       published (e.g. Watchtower, a webhook, a cron pull, or however sae4health
       currently updates)?

Happy to share the GitHub repo, the Dockerfile, or hop on a call to walk through it.
Thanks very much for the help!

Best,
Victoria
