Subject: Deploying a new Shiny app (IndicatorComparison) on the Stats server

Hi Asa,

We have a new R Shiny app, "IndicatorComparison," that we'd like to deploy on the
UW Statistics server. It's set up the same way as the sae4health app
(https://github.com/wu-thomas/sae4health): containerized with Docker and
auto-published to the GitHub Container Registry (ghcr.io) by a GitHub Actions
workflow on every push. The app is lightweight — it just reads pre-modeled CSV
estimates and draws scatterplots, so there's no modeling, and no spatial/INLA
dependencies. The container serves on port 3838.

A few things I'd like to check on your end to get it connected and deployed:

1. Data hosting / URL. The app reads its estimates over https from:
       https://sites.stat.washington.edu/indicatorcomparison/Gates_Indicator_Comparison/estimates/<Country>/combined_results.csv
   This is its own base path (separate from sae4health's). Can you confirm:
     - Can you set up https://sites.stat.washington.edu/indicatorcomparison/ as the
       app's base path, or should it live at a different URL?
     - Where should we place the "Gates_Indicator_Comparison/estimates/..." files on
       the server so they're web-readable, and can you confirm they'll be reachable
       at that URL? (We can hand off the per-country combined_results.csv files.)

2. Pulling and running the image. The CI publishes the (public) image
   ghcr.io/victoriaknutson/indicatorcomparison:latest. Could you confirm how the
   server should pull and run it (the same way sae4health is run)? Specifically:
     - The image is public, so the server can pull from ghcr.io without credentials.
     - What's the mechanism to auto-update the running container when a new image is
       published (e.g. Watchtower, a webhook, a cron pull, or however sae4health
       currently updates)?

3. Reverse proxy / URL path. The container listens on port 3838. What public URL
   path would you map it to (e.g. https://rsc.stat.washington.edu/IndicatorComparison/
   or similar), and is the nginx/proxy config something you handle on your side?

Happy to share the GitHub repo, the Dockerfile, or hop on a call to walk through it.
Thanks very much for the help!

Best,
Victoria
