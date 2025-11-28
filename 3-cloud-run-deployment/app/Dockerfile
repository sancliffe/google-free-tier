# Use an official Node.js runtime as a parent image
# Upgraded to 20-slim (Active LTS)
FROM node:20-slim

# Set the working directory in the container
WORKDIR /usr/src/app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install app dependencies
# Use 'npm ci' for reproducible builds.
RUN npm ci --only=production

# Bundle app source
# Change ownership of the files to the 'node' user
COPY --chown=node:node . .
# Switch to the non-root 'node' user for security
USER node

# Your app binds to port 8080, so expose it
EXPOSE 8080

# Define the command to run your app
CMD [ "node", "server.js" ]