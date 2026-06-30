# IndicatorComparison -- DHS Indicator Scatterplot Shiny app
# Mirrors the sae4health deployment (rocker/shiny base, port 3838) but with a
# much lighter dependency set: this app only reads pre-modeled CSV estimates and
# renders ggplot2/plotly, so no spatial (gdal/geos/proj) or modeling libraries
# are required.
FROM rocker/shiny:4.4

ENV DEBIAN_FRONTEND=noninteractive

# System libraries needed by the R packages below:
#   libcurl/libssl  -> reading estimates over https with url()
#   libxml2         -> plotly / xml2
#   font + image    -> ggplot2 / ragg text + raster rendering
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

# Pin a dated Posit Package Manager snapshot for reproducible binary installs.
# (shiny is already present in the rocker/shiny base image.)
RUN R -e "install.packages( \
      c('dplyr','tidyr','readr','ggplot2','plotly'), \
      repos = 'https://packagemanager.posit.co/cran/__linux__/jammy/2025-06-01' \
    )"

WORKDIR /srv/shiny-server

# Copy the app (app.R, global.R, data/indicatorList.csv). The server fetches
# estimates over the network at runtime, so no data is baked into the image.
COPY . .

EXPOSE 3838

# In production, point the app at the UW Stats estimates with:
#   docker run -e INDICATOR_SERVER_LINK="https://.../" -p 3838:3838 <image>
CMD ["R", "-e", "setwd('/srv/shiny-server'); app <- source('app.R', chdir = TRUE)$value; shiny::runApp(app, host = '0.0.0.0', port = 3838)"]
