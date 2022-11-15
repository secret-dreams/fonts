FROM ruby:2.7-alpine 
LABEL maintainer="valflores@gmail.com"

RUN apk --no-cache add --virtual .build-deps build-base gcc && \
    apk --no-cache add --virtual .fontpreview xdotool fzf imagemagick && \ 
    apk --no-cache add --virtual .fontreduce python3 python3-dev py-pip && \
    pip install fonttools Brotli zopfli

WORKDIR /app

COPY bin/ ./bin
RUN gem install bundler && gem list && cd bin/ && bundle install

ENV PATH="/app/bin:${PATH}"

CMD ["fonts.rb", "--help"]