FROM perl:5.38-slim

WORKDIR /app

COPY cpanfile /app/cpanfile
RUN cpanm --notest Carton && carton install --deployment --without=test

COPY . /app

EXPOSE 5000

ENV DANCER_ENVIRONMENT=production
CMD ["carton", "exec", "plackup", "-s", "Starman", "-Ilib", "-p", "5000", "app.psgi"]
