# Use the official Ruby 3.4.10 image as the base image
FROM ruby:3.4.10

# Set the working directory within the container
WORKDIR /app

# The image precompiles assets and migrates the production database, so run it in production by default
ENV RAILS_ENV=production

# Copy the Gemfile and Gemfile.lock into the container
COPY Gemfile Gemfile.lock ./

# Install bundler and the dependencies specified in Gemfile
RUN bundle install

# Copy the application code into the container
COPY . .

# Install Node.js, Yarn, and apt-utils
RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main' | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get -qy update && \
    apt-get -qy install nodejs && \
    npm install --global yarn && \
    groupadd --system app && \
    useradd --system --gid app --home-dir /app app && \
    chown -R app:app /app

USER app

# Precompile assets
RUN yarn install --check-files --production && \
    yarn build && \
    EDITOR=vim rails credentials:edit && \
    NODE_ENV=production \
    bundle exec rails assets:precompile db:create db:migrate

# Expose the port that the application will run on
EXPOSE 3000

# Start the application server
CMD ["bash", "-c", "rm -f tmp/pids/server.pid && bundle exec rails server -b 0.0.0.0 -p 3000"]



