# Use an official Node.js runtime as a parent image
# Upgraded to 20-slim (Active LTS)
FROM node:20-slim

# Set the working directory in the container
WORKDIR /usr/src/app

# Download dumb-init directly (smaller)
RUN wget -O /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_x86_64 \
    && echo "0e77451996520c9955767b7891ad607730e527d2c3e1e073007f309a47321489  /usr/bin/dumb-init" | sha256sum -c - \
    && chmod +x /usr/bin/dumb-init

WORKDIR /usr/src/app
COPY package.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Bundle app source
# Change ownership of the files to the 'node' user
COPY --chown=node:node . .

# Switch to the non-root 'node' user for security
USER node

# Your app binds to port 8080, so expose it
EXPOSE 8080

# Use dumb-init as the entrypoint
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Define the command to run your app
CMD [ "node", "server.js" ]