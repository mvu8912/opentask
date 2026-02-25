FROM perl:5.38-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends uwsgi-core uwsgi-plugin-psgi \
    && rm -rf /var/lib/apt/lists/*

COPY . /app
RUN cpanm --notest --installdeps .

EXPOSE 5000

ENV DANCER_ENVIRONMENT=production
CMD ["uwsgi", "--http", ":5000", "--plugins", "psgi", "--psgi", "/app/app.psgi", "--master", "--processes", "2", "--threads", "2", "--die-on-term"]
