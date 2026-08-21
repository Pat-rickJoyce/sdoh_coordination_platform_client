# Use the official Ruby 2.7.5 image as the base image
FROM ruby:2.7.5

# Set the working directory within the container
WORKDIR /app

# Copy the Gemfile and Gemfile.lock into the container
COPY Gemfile Gemfile.lock ./

# Install bundler and the dependencies specified in Gemfile
RUN gem install bundler -v 2.4.22 && bundle install

# Copy the application code into the container
COPY . .

# Install Node.js, Yarn, and apt-utils
RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main' | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get -qy update && \
    apt-get -qy install nodejs && \
    npm install --global yarn

# Precompile assets
RUN yarn install --check-files --production
RUN EDITOR=vim rails credentials:edit

# Seed the prod database... Remove if using manually creating/migrating a Postgres DB
RUN RAILS_ENV=production \
  NODE_ENV=production \
  bundle exec rails assets:precompile db:create db:migrate

# Expose the port that the application will run on
EXPOSE 3000

# Start the application server
CMD ["bash", "-c", "rm -f tmp/pids/server.pid && bundle exec rails server -p 3000"]



